defmodule Archethic.P2P.Message.GetUnspentOutputsTest do
  @moduledoc false
  use ExUnit.Case
  import ArchethicCase

  alias Archethic.UTXO
  alias Archethic.P2P.Message.GetUnspentOutputs
  alias Archethic.P2P.Message.UnspentOutputList

  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.VersionedUnspentOutput
  alias Archethic.TransactionChain.Transaction.ValidationStamp.LedgerOperations.UnspentOutput

  import Mock
  import Mox

  setup :set_mox_global

  test "serialization/deserialization" do
    address = random_address()

    msg = %GetUnspentOutputs{address: address}

    assert {^msg, <<>>} =
             msg
             |> GetUnspentOutputs.serialize()
             |> GetUnspentOutputs.deserialize()

    msg = %GetUnspentOutputs{address: address, offset: :crypto.strong_rand_bytes(32)}

    assert {^msg, <<>>} =
             msg
             |> GetUnspentOutputs.serialize()
             |> GetUnspentOutputs.deserialize()

    msg = %GetUnspentOutputs{address: address, offset: :crypto.strong_rand_bytes(32), limit: 10}

    assert {^msg, <<>>} =
             msg
             |> GetUnspentOutputs.serialize()
             |> GetUnspentOutputs.deserialize()
  end

  describe "process/2" do
    setup do
      last_chain_sync_date = DateTime.utc_now() |> DateTime.truncate(:millisecond)

      MockDB
      |> stub(:get_last_chain_address, fn _ -> {random_address(), last_chain_sync_date} end)

      :ok
    end

    test "should get last chain address and return it's timestamp" do
      address = random_address()
      last_chain_sync_date = DateTime.utc_now() |> DateTime.truncate(:millisecond)

      MockDB
      |> expect(:get_last_chain_address, fn _ -> {random_address(), last_chain_sync_date} end)

      expected_utxos = []

      with_mock(UTXO, stream_unspent_outputs: fn ^address -> expected_utxos end) do
        assert %UnspentOutputList{
                 unspent_outputs: ^expected_utxos,
                 offset: nil,
                 more?: false,
                 last_chain_sync_date: ^last_chain_sync_date
               } =
                 GetUnspentOutputs.process(
                   %GetUnspentOutputs{address: address},
                   random_public_key()
                 )
      end
    end

    test "should return no utxo when account is empty" do
      address = random_address()

      expected_utxos = []

      with_mock(UTXO, stream_unspent_outputs: fn _address -> expected_utxos end) do
        assert %UnspentOutputList{
                 unspent_outputs: ^expected_utxos,
                 offset: nil,
                 more?: false
               } =
                 GetUnspentOutputs.process(
                   %GetUnspentOutputs{address: address},
                   random_public_key()
                 )
      end
    end

    test "should return the entire list of utxos if less than threshold" do
      address = random_address()
      now = DateTime.utc_now()

      utxos = [
        %VersionedUnspentOutput{
          protocol_version: current_protocol_version(),
          unspent_output: %UnspentOutput{
            amount: 1,
            from: random_address(),
            type: :UCO,
            timestamp: now
          }
        },
        %VersionedUnspentOutput{
          protocol_version: current_protocol_version(),
          unspent_output: %UnspentOutput{
            amount: 2,
            from: random_address(),
            type: :UCO,
            timestamp: now
          }
        },
        %VersionedUnspentOutput{
          protocol_version: current_protocol_version(),
          unspent_output: %UnspentOutput{
            amount: 3,
            from: random_address(),
            type: :UCO,
            timestamp: now
          }
        }
      ]

      expected_offset = utxos |> List.last() |> VersionedUnspentOutput.hash()

      with_mock(UTXO, stream_unspent_outputs: fn _address -> utxos end) do
        assert %UnspentOutputList{
                 unspent_outputs: ^utxos,
                 offset: ^expected_offset,
                 more?: false
               } =
                 GetUnspentOutputs.process(
                   %GetUnspentOutputs{address: address},
                   random_public_key()
                 )
      end
    end

    test "should return the utxos after offset" do
      address = random_address()
      now = DateTime.utc_now()

      utxos = [
        %VersionedUnspentOutput{
          protocol_version: current_protocol_version(),
          unspent_output: %UnspentOutput{
            amount: 1,
            from: random_address(),
            type: :UCO,
            timestamp: now
          }
        },
        %VersionedUnspentOutput{
          protocol_version: current_protocol_version(),
          unspent_output: %UnspentOutput{
            amount: 2,
            from: random_address(),
            type: :UCO,
            timestamp: now
          }
        },
        %VersionedUnspentOutput{
          protocol_version: current_protocol_version(),
          unspent_output: %UnspentOutput{
            amount: 3,
            from: random_address(),
            type: :UCO,
            timestamp: now
          }
        }
      ]

      [first_utxo | expected_utxos] = utxos

      request_offset = VersionedUnspentOutput.hash(first_utxo)
      expected_offset = expected_utxos |> List.last() |> VersionedUnspentOutput.hash()

      with_mock(UTXO, stream_unspent_outputs: fn _address -> utxos end) do
        assert %UnspentOutputList{
                 unspent_outputs: ^expected_utxos,
                 offset: ^expected_offset,
                 more?: false
               } =
                 GetUnspentOutputs.process(
                   %GetUnspentOutputs{address: address, offset: request_offset},
                   random_public_key()
                 )
      end
    end

    test "should  return a subset of the utxos" do
      address = random_address()
      now = DateTime.utc_now()

      # 51 is the size in Bytes of a UCO utxo serialized
      threshold = Keyword.get(Application.get_env(:archethic, GetUnspentOutputs, []), :threshold)
      max_utxos = div(threshold, 51)

      # generate a few more than we can fit in a message
      utxos =
        Enum.map(1..(max_utxos + 10), fn i ->
          %VersionedUnspentOutput{
            protocol_version: current_protocol_version(),
            unspent_output: %UnspentOutput{
              amount: i,
              from: random_address(),
              type: :UCO,
              timestamp: now
            }
          }
        end)

      expected_utxos = Enum.slice(utxos, 0..(max_utxos - 1))

      expected_offset = utxos |> Enum.at(max_utxos - 1) |> VersionedUnspentOutput.hash()

      with_mock(UTXO, stream_unspent_outputs: fn _address -> utxos end) do
        assert %UnspentOutputList{
                 unspent_outputs: ^expected_utxos,
                 offset: ^expected_offset,
                 more?: true
               } =
                 GetUnspentOutputs.process(
                   %GetUnspentOutputs{address: address},
                   random_public_key()
                 )
      end
    end
  end
end
