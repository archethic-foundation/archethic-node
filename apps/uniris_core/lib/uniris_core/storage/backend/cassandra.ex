defmodule UnirisCore.Storage.CassandraBackend do
  @moduledoc false


  @insert_transaction_stmt """
  INSERT INTO uniris.transactions(
      address,
      type,
      timestamp,
      data,
      previous_public_key,
      previous_signature,
      origin_signature,
      validation_stamp,
      cross_validation_stamps)
    VALUES(
      :address,
      :type,
      :timestamp,
      :data,
      :previous_public_key,
      :previous_signature,
      :origin_signature,
      :validation_stamp,
      :cross_validation_stamps
    )
  """

  @insert_transaction_chain_stmt """
  INSERT INTO uniris.transaction_chains(
      chain_address,
      bucket,
      transaction_address,
      type,
      timestamp,
      data,
      previous_public_key,
      previous_signature,
      origin_signature,
      validation_stamp,
      cross_validation_stamps)
    VALUES(
      :chain_address,
      :bucket,
      :transaction_address,
      :type,
      :timestamp,
      :data,
      :previous_public_key,
      :previous_signature,
      :origin_signature,
      :validation_stamp,
      :cross_validation_stamps
    )
  """

  alias UnirisCore.Transaction
  alias UnirisCore.TransactionData
  alias UnirisCore.TransactionData.Keys
  alias UnirisCore.TransactionData.Ledger
  alias UnirisCore.TransactionData.UCOLedger
  alias UnirisCore.TransactionData.Ledger.Transfer
  alias UnirisCore.Transaction.ValidationStamp
  alias UnirisCore.Transaction.ValidationStamp.LedgerMovements
  alias UnirisCore.Transaction.ValidationStamp.NodeMovements
  alias UnirisCore.Transaction.ValidationStamp.LedgerMovements.UTXO
  alias __MODULE__.ChainQueryWorker
  alias __MODULE__.ChainQuerySupervisor

  defdelegate child_spec(opts), to: __MODULE__.Supervisor

  @behaviour UnirisCore.Storage.BackendImpl

  @impl true
  def list_transactions() do
    Xandra.stream_pages!(:xandra_conn, "SELECT * FROM uniris.transactions", _params = [])
    |> Stream.flat_map(& &1)
    |> Stream.map(&format_result_to_transaction/1)
    |> Enum.to_list()
  end

  @impl true
  def get_transaction(address) do
    prepared = Xandra.prepare!(:xandra_conn, "SELECT * FROM uniris.transactions WHERE address=?")

    Xandra.execute!(:xandra_conn, prepared, [address |> Base.encode16()])
    |> Enum.to_list()
    |> case do
      [] ->
        {:error, :transaction_not_exists}

      [page] ->
        {:ok, format_result_to_transaction(page)}
    end
  end

  @impl true
  def get_transaction_chain(address) do
    Supervisor.which_children(ChainQuerySupervisor)
    |> Enum.map(fn {_, pid, _, _} -> pid end)
    |> Task.async_stream(&ChainQueryWorker.get(&1, address))
    |> Enum.flat_map(fn {:ok, res} -> res end)
    |> case do
      [] ->
        {:error, :transaction_chain_not_exists}
      chain ->
        {:ok, chain}
    end
  end

  @impl true
  def write_transaction(tx = %Transaction{}) do
    prepared = Xandra.prepare!(:xandra_conn, @insert_transaction_stmt)
    {:ok, _} = Xandra.execute(:xandra_conn, prepared, transaction_write_parameters(tx))
    :ok
  end

  @impl true
  def write_transaction_chain(
        chain = [%Transaction{address: chain_address, timestamp: timestamp} | _]
      ) do
    bucket = rem(DateTime.to_unix(timestamp), 10)
    transaction_prepared = Xandra.prepare!(:xandra_conn, @insert_transaction_stmt)
    chain_prepared = Xandra.prepare!(:xandra_conn, @insert_transaction_chain_stmt)

    Task.async_stream(chain, fn tx ->
      {:ok, _} = Xandra.execute(:xandra_conn, transaction_prepared, transaction_write_parameters(tx))
      {:ok, _} = Xandra.execute(:xandra_conn, chain_prepared, transaction_chain_write_parameters(chain_address, bucket, tx))
    end)
    |> Stream.run()
  end

  defp transaction_write_parameters(tx = %Transaction{}) do
    %{
      "address" => tx.address |> Base.encode16(),
      "type" => Atom.to_string(tx.type),
      "timestamp" => tx.timestamp,
      "data" => %{
        "content" => tx.data.content,
        "code" => tx.data.code,
        "keys" => %{
          "authorized_keys" =>
            tx.data.keys.authorized_keys
            |> Enum.map(fn {k, v} ->
              {Base.encode16(k), Base.encode16(v)}
            end)
            |> Enum.into(%{}),
          "secret" => tx.data.keys.secret |> Base.encode16()
        },
        "ledger" => %{
          "uco" => %{
            "transfers" =>
              Enum.map(tx.data.ledger.uco.transfers, fn %{to: to, amount: amount} ->
                %{
                  "recipient" => to |> Base.encode16(),
                  "amount" => amount
                }
              end)
          }
        },
        "recipients" => Enum.map(tx.data.recipients, &Base.encode16/1)
      },
      "previous_public_key" => tx.previous_public_key |> Base.encode16(),
      "previous_signature" => tx.previous_signature |> Base.encode16(),
      "origin_signature" => tx.origin_signature |> Base.encode16(),
      "validation_stamp" => %{
        "proof_of_work" => tx.validation_stamp.proof_of_work |> Base.encode16(),
        "proof_of_integrity" => tx.validation_stamp.proof_of_integrity |> Base.encode16(),
        "ledger_movements" => %{
          "uco" => %{
            "previous_ledger_summary" => %{
              "senders" =>
                Enum.map(
                  tx.validation_stamp.ledger_movements.uco.previous.from,
                  &Base.encode16/1
                ),
              "amount" => tx.validation_stamp.ledger_movements.uco.previous.amount
            },
            "next_ledger_summary" => %{
              "amount" => tx.validation_stamp.ledger_movements.uco.next
            }
          }
        },
        "node_movements" => %{
          "fee" => tx.validation_stamp.node_movements.fee,
          "rewards" =>
            Enum.map(tx.validation_stamp.node_movements.rewards, fn {node, amount} ->
              %{
                "node" => node |> Base.encode16(),
                "amount" => amount
              }
            end)
        },
        "signature" => tx.validation_stamp.signature |> Base.encode16()
      },
      "cross_validation_stamps" =>
        Enum.map(tx.cross_validation_stamps, fn {signature, inconsistencies, node_public_key} ->
          %{
            "node" => node_public_key |> Base.encode16(),
            "signature" => signature |> Base.encode16(),
            "inconsistencies" => Enum.map(inconsistencies, &Atom.to_string/1)
          }
        end)
    }
  end

  defp transaction_chain_write_parameters(chain_address, bucket, tx = %Transaction{}) do
    transaction_write_parameters(tx)
    |> Map.put("chain_address", chain_address |> Base.encode16)
    |> Map.put("bucket", bucket)
    |> Map.delete("address")
    |> Map.put("transaction_address", tx.address |> Base.encode16)
  end

  def format_result_to_transaction(%{
         "address" => address,
         "type" => type,
         "timestamp" => timestamp,
         "data" => %{
           "content" => content,
           "code" => code,
           "keys" => %{
             "authorized_keys" => authorized_keys,
             "secret" => secret
           },
           "ledger" => %{
             "uco" => %{
               "transfers" => transfers
             }
           },
           "recipients" => recipients
         },
         "previous_public_key" => previous_public_key,
         "previous_signature" => previous_signature,
         "origin_signature" => origin_signature,
         "validation_stamp" => %{
           "proof_of_work" => pow,
           "proof_of_integrity" => poi,
           "ledger_movements" => %{
             "uco" => %{
               "previous_ledger_summary" => %{
                 "senders" => previous_senders,
                 "amount" => previous_amount
               },
               "next_ledger_summary" => %{
                 "amount" => next_amount
               }
             }
           },
           "node_movements" => %{
             "fee" => fee,
             "rewards" => rewards
           },
           "signature" => signature
         },
         "cross_validation_stamps" => cross_validation_stamps
       }) do
    %Transaction{
      address: address |> Base.decode16!(),
      type: String.to_atom(type),
      data: %TransactionData{
        content: content,
        code: code,
        keys: %Keys{
          authorized_keys: Enum.map(authorized_keys, fn {k, v} ->
            { Base.decode16!(k), Base.decode16!(v)}
          end) |> Enum.into(%{}),
          secret: secret |> Base.decode16!()
        },
        ledger: %Ledger{
          uco: %UCOLedger{
            transfers: Enum.map(transfers, fn %{"recipient" => to, "amount" => amount} ->
              %Transfer{
                amount: amount,
                to: to |> Base.decode16!()
              }
            end)
          }
        },
        recipients: Enum.map(recipients, &Base.decode16!/1)
      },
      timestamp: timestamp,
      previous_public_key: previous_public_key |> Base.decode16!(),
      previous_signature: previous_signature |> Base.decode16!(),
      origin_signature: origin_signature |> Base.decode16!(),
      validation_stamp: %ValidationStamp{
        proof_of_work: pow |> Base.decode16!(),
        proof_of_integrity: poi |> Base.decode16!(),
        ledger_movements: %LedgerMovements{
          uco: %UTXO{
            previous: %{
              from: Enum.map(previous_senders, &Base.decode16!/1),
              amount: previous_amount
            },
            next: next_amount
          }
        },
        node_movements: %NodeMovements{
          fee: fee,
          rewards: Enum.map(rewards, fn %{ "node" => node, "amount" => amount} ->
            {node |> Base.decode16!(), amount}
          end)
        },
        signature: signature |> Base.decode16!
      },
      cross_validation_stamps: Enum.map(cross_validation_stamps, fn %{"node" => node, "signature" => signature, "inconsistencies" => inconsistencies} ->
        { signature |> Base.decode16!(), Enum.map(inconsistencies, &String.to_atom/1), node |> Base.decode16!() }
      end)
    }
  end
end
