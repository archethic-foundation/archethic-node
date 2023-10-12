defmodule ArchethicWeb.API.REST.TransactionController do
  @moduledoc """
  DEPRECATED. WILL BE REPLACED BY JSONRPC API
  """

  use ArchethicWeb.API, :controller

  alias Archethic.Contracts
  alias Archethic.Contracts.Contract.ActionWithoutTransaction
  alias Archethic.Contracts.Contract.ActionWithTransaction
  alias Archethic.Contracts.Contract.Failure
  alias Archethic.TransactionChain.Transaction
  alias Archethic.TransactionChain.Transaction.ValidationStamp
  alias Archethic.TransactionChain.TransactionData

  alias Archethic.Mining
  alias Archethic.OracleChain

  alias ArchethicWeb.API.TransactionPayload
  alias ArchethicWeb.Explorer.ErrorView
  alias ArchethicWeb.TransactionSubscriber

  require Logger

  def new(conn, params = %{}) do
    case TransactionPayload.changeset(params) do
      {:ok, changeset = %{valid?: true}} ->
        tx =
          changeset
          |> TransactionPayload.to_map()
          |> Transaction.cast()

        tx_address = tx.address

        try do
          if Archethic.transaction_exists?(tx_address) do
            conn |> put_status(422) |> json(%{status: "error - transaction already exists!"})
          else
            send_transaction(conn, tx)
          end
        catch
          e ->
            Logger.error("Cannot get transaction summary - #{inspect(e)}")
            conn |> put_status(504) |> json(%{status: "error - networking error"})
        end

      {:ok, changeset} ->
        Logger.debug(
          "Invalid transaction #{inspect(Ecto.Changeset.traverse_errors(changeset, &ArchethicWeb.WebUtils.translate_error/1))}"
        )

        conn
        |> put_status(400)
        |> put_view(ErrorView)
        |> render("400.json", changeset: changeset)
    end
  end

  defp send_transaction(conn, tx = %Transaction{}) do
    :ok = Archethic.send_new_transaction(tx, forward?: true)
    TransactionSubscriber.register(tx.address, System.monotonic_time())

    conn
    |> put_status(201)
    |> json(%{
      transaction_address: Base.encode16(tx.address),
      status: "pending"
    })
  end

  def last_transaction_content(conn, params = %{"address" => address}) do
    with {:ok, address} <- Base.decode16(address, case: :mixed),
         {:ok, %Transaction{address: last_address, data: %TransactionData{content: content}}} <-
           Archethic.get_last_transaction(address) do
      mime_type = Map.get(params, "mime", "text/plain")

      etag = Base.encode16(last_address, case: :lower)

      cached? =
        case List.first(get_req_header(conn, "if-none-match")) do
          got_etag when got_etag == etag ->
            true

          _ ->
            false
        end

      conn =
        conn
        |> put_resp_content_type(mime_type, "utf-8")
        |> put_resp_header("content-encoding", "gzip")
        |> put_resp_header("cache-control", "public")
        |> put_resp_header("etag", etag)

      if cached? do
        send_resp(conn, 304, "")
      else
        send_resp(conn, 200, :zlib.gzip(content))
      end
    else
      _reason ->
        send_resp(conn, 404, "Not Found")
    end
  end

  def transaction_fee(conn, tx) do
    case TransactionPayload.changeset(tx) do
      {:ok, changeset = %{valid?: true}} ->
        timestamp = DateTime.utc_now()

        previous_price =
          timestamp
          |> OracleChain.get_last_scheduling_date()
          |> OracleChain.get_uco_price()

        uco_eur = previous_price |> Keyword.fetch!(:eur)
        uco_usd = previous_price |> Keyword.fetch!(:usd)

        # not possible to have a contract's state here
        fee =
          changeset
          |> TransactionPayload.to_map()
          |> Transaction.cast()
          |> Mining.get_transaction_fee(nil, uco_usd, timestamp)

        conn
        |> put_status(:ok)
        |> json(%{
          "fee" => fee,
          "rates" => %{
            "usd" => uco_usd,
            "eur" => uco_eur
          }
        })

      {:ok, changeset} ->
        conn
        |> put_status(:bad_request)
        |> put_view(ErrorView)
        |> render("400.json", changeset: changeset)
    end
  end

  @doc """
  This controller, Fetch the recipients contract and simulate the transaction, managing possible
  exits from contract execution
  """
  def simulate_contract_execution(
        conn,
        params = %{}
      ) do
    case TransactionPayload.changeset(params) do
      {:ok, changeset = %{valid?: true}} ->
        trigger_tx =
          %Transaction{data: %TransactionData{recipients: recipients}} =
          changeset
          |> TransactionPayload.to_map()
          |> Transaction.cast()
          |> then(fn tx ->
            # We add a dummy ValidationStamp to the transaction
            # because the Interpreter requires a validated transaction
            %Transaction{tx | validation_stamp: ValidationStamp.generate_dummy()}
          end)

        # for now the Simulate Contract Execution does not work with named action
        recipients = Enum.map(recipients, & &1.address)

        results =
          Task.Supervisor.async_stream_nolink(
            Archethic.TaskSupervisor,
            recipients,
            &fetch_recipient_tx_and_simulate(&1, trigger_tx),
            on_timeout: :kill_task,
            timeout: 5000
          )
          |> Stream.zip(recipients)
          |> Stream.map(fn
            {{:ok, :ok}, recipient} ->
              %{
                "valid" => true,
                "recipient_address" => Base.encode16(recipient)
              }

            {{:ok, {:error, reason}}, recipient} ->
              %{
                "valid" => false,
                "reason" => reason,
                "recipient_address" => Base.encode16(recipient)
              }

            {{:exit, :timeout}, recipient} ->
              %{
                "valid" => false,
                "reason" => "A contract timed out",
                "recipient_address" => Base.encode16(recipient)
              }

            {{:exit, reason}, recipient} ->
              %{
                "valid" => false,
                "reason" => format_exit_reason(reason),
                "recipient_address" => Base.encode16(recipient)
              }
          end)
          |> Enum.to_list()

        case results do
          [] ->
            conn
            |> put_status(:ok)
            |> json([
              %{"valid" => false, "reason" => "There are no recipients in the transaction"}
            ])

          _ ->
            conn
            |> put_status(:ok)
            |> json(results)
        end

      {:ok, changeset} ->
        error_details =
          Ecto.Changeset.traverse_errors(
            changeset,
            &ArchethicWeb.WebUtils.translate_error/1
          )

        json_body =
          Map.merge(error_details, %{"valid" => false, "reason" => "Query validation failled"})

        conn
        |> put_status(:ok)
        |> json([json_body])
    end
  end

  defp fetch_recipient_tx_and_simulate(recipient_address, trigger_tx) do
    with {:ok, contract_tx} <- Archethic.get_last_transaction(recipient_address),
         maybe_state_utxo <- Contracts.State.get_utxo_from_transaction(contract_tx),
         {:ok, contract} <-
           Contracts.from_transaction(contract_tx) do
      case Contracts.execute_trigger(
             {:transaction, nil, nil},
             contract,
             trigger_tx,
             nil,
             maybe_state_utxo
           ) do
        %ActionWithTransaction{} ->
          :ok

        %ActionWithoutTransaction{} ->
          {:error, "Execution success, but the contract did not produce a next transaction"}

        %Failure{user_friendly_error: reason} ->
          {:error, reason}
      end
    else
      # search_transaction errors
      {:error, :transaction_not_exists} ->
        {:error, "There is no transaction at recipient address."}

      {:error, :invalid_transaction} ->
        {:error, "The transaction is marked as invalid."}

      {:error, :network_issue} ->
        {:error, "Network issue, please try again later."}

      # parse_contract errors
      {:error, reason} when is_binary(reason) ->
        {:error, reason}
    end
  end

  defp format_exit_reason({error, stacktrace}) do
    formatted_error =
      case error do
        atom when is_atom(atom) ->
          # ex: :badarith
          inspect(atom)

        {atom, _} when is_atom(atom) ->
          # ex: :badmatch
          inspect(atom)

        _ ->
          "unknown error"
      end

    Enum.reduce_while(
      stacktrace,
      "A contract exited with error: #{formatted_error}",
      fn
        {:elixir_eval, _, _, [file: 'nofile', line: line]}, acc ->
          {:halt, acc <> " (line: #{line})"}

        _, acc ->
          {:cont, acc}
      end
    )
  end

  defp format_exit_reason(_) do
    "A contract exited with an unknown error"
  end
end
