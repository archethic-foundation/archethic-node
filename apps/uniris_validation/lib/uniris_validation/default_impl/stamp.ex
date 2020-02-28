defmodule UnirisValidation.DefaultImpl.Stamp do
  @moduledoc false

  alias UnirisChain.Transaction
  alias UnirisChain.Transaction.ValidationStamp
  alias UnirisChain.Transaction.ValidationStamp.LedgerMovements
  alias UnirisChain.Transaction.ValidationStamp.NodeMovements
  alias UnirisValidation.DefaultImpl.Reward
  alias UnirisValidation.DefaultImpl.Fee
  alias UnirisValidation.DefaultImpl.ProofOfIntegrity
  alias UnirisValidation.DefaultImpl.ProofOfWork
  alias UnirisValidation.DefaultImpl.UTXO
  alias UnirisCrypto, as: Crypto
  alias UnirisElection, as: Election
  alias UnirisNetwork, as: Network

  @typep pow_result :: {:ok, binary()} | {:error, :not_found}

  @doc """
  Create a new validation stamp based on data coming from the mining

  ## Examples

     iex> UnirisCrypto.generate_deterministic_keypair("seed", persistence: true)
     iex> tx = %UnirisChain.Transaction{
     ...>   address: "A9BCEB532873BAB3BDF5DD41594CC57CE0AC5E1073B50F4CE3FA6DDF4F3DD2F1",
     ...>   type: :transfer,
     ...>   timestamp: 1582591494,
     ...>   data: %{
     ...>     ledger: %{
     ...>       uco: %{
     ...>         transfers: [%{to: "D764BD45B853C689E2BA6D0357E2314F087E402F1F66449B282E5DEDB827EAFD", amount: 5}]
     ...>       }
     ...>     }
     ...>   },
     ...>   previous_public_key: "",
     ...>   previous_signature: "",
     ...>   origin_signature: ""
     ...> }
     iex> unspent_outputs = [
     ...>   %UnirisChain.Transaction{
     ...>   address: "239CCBB96728772F42C5DC3E1AC236208CDA2E8AAD3EF0FF8838081A7AFD4AF9",
     ...>   type: :transfer,
     ...>   timestamp: 1582591506,
     ...>   data: %{
     ...>     ledger: %{
     ...>       uco: %{
     ...>         transfers: [%{to: tx.address, amount: 10}]
     ...>       }
     ...>     }
     ...>   },
     ...>   previous_public_key: "",
     ...>   previous_signature: "",
     ...>   origin_signature: ""
     ...> }]
     iex> chain = [ %UnirisChain.Transaction{
     ...>   address: "4A3FE2512D43D40E80D947867428DD17EDBF72D93E9673A4382A638161081063",
     ...>   type: :transfer,
     ...>   timestamp: 1582591518 ,
     ...>   data: %{},
     ...>   previous_public_key: "",
     ...>   previous_signature: "",
     ...>   origin_signature: "",
     ...>   validation_stamp: %UnirisChain.Transaction.ValidationStamp{
     ...>     proof_of_work: "DA96299EC4777FB122E5CF127AAE58020617EC42D3A8F59A63F7A897C46CB52C",
     ...>     proof_of_integrity: "44EF4E8E43B08B6E18A691D8F9A5F8822ECAD1D8C7FE7BAC798FF632F821AC80",
     ...>     ledger_movements: %UnirisChain.Transaction.ValidationStamp.LedgerMovements{},
     ...>     node_movements: %UnirisChain.Transaction.ValidationStamp.NodeMovements{
     ...>      fee: 1.0,
     ...>      rewards: []
     ...>     },
     ...>     signature: "4B38788522E29C3ED6D06FFD406B2E0D1479BF53A98A08F3E97BF6BF8020165012F95DA012913B92FB387B71F9324514E688D85FCD7FEB03CB376D3A31F4EF52"
     ...>   }
     ...> }]
     iex> UnirisValidation.DefaultImpl.Stamp.create_validation_stamp(tx, chain, unspent_outputs, "welcome_node_public_key", "coordinator_public_key", ["validator_public_key"], ["storage_node_public_key"], {:ok, "ABF22E362D4947C7604D103C88C6728C6CAAF9D20AE72FB317A2E475EE732572"})
     %UnirisChain.Transaction.ValidationStamp{
     proof_of_work: "ABF22E362D4947C7604D103C88C6728C6CAAF9D20AE72FB317A2E475EE732572",
     proof_of_integrity: <<0, 35, 255, 132, 117, 130, 182, 105, 55, 250, 14, 36, 54, 165, 149, 183, 21, 167, 183, 184, 250, 200, 82, 251, 147, 170, 213, 214, 178,
       159, 72, 182, 174>>,
     ledger_movements: %UnirisChain.Transaction.ValidationStamp.LedgerMovements{
         uco: %UnirisChain.Transaction.ValidationStamp.LedgerMovements.UTXO{
           previous: %{from: ["239CCBB96728772F42C5DC3E1AC236208CDA2E8AAD3EF0FF8838081A7AFD4AF9"], amount: 10},
           next: 4.9
         }
       },
       node_movements: %UnirisChain.Transaction.ValidationStamp.NodeMovements{
         fee: 0.1,
         rewards: [{"welcome_node_public_key", 0.0005}, {"coordinator_public_key", 0.009500000000000001}, {"validator_public_key", 0.04000000000000001 }, {"storage_node_public_key", 0.05}]
       },
       signature: <<76, 61, 65, 10, 193, 142, 142, 209, 93, 46, 126, 74, 209, 183,
       213, 42, 177, 68, 1, 25, 231, 189, 116, 138, 192, 78, 92, 179, 251, 9, 36,
       84, 127, 203, 0, 20, 214, 10, 87, 85, 144, 150, 217, 233, 217, 126, 201,
       131, 132, 45, 122, 40, 27, 177, 207, 167, 252, 9, 252, 131, 14, 92, 238, 7>>
       }
  """
  @spec create_validation_stamp(
          transaction :: Transaction.pending(),
          previous_chain :: list(Transaction.validated()),
          unspent_outputs :: list(Transaction.validated()),
          welcome_node :: binary(),
          coordinator_node :: binary(),
          cross_validation_nodes :: list(binary()),
          previous_storage_nodes :: list(binary()),
          proof_of_work :: pow_result
        ) :: ValidationStamp.t()
  def create_validation_stamp(
        tx = %Transaction{},
        previous_chain,
        unspent_outputs,
        welcome_node,
        coordinator_node,
        cross_validation_nodes,
        previous_storage_nodes,
        pow_result
      ) do
    fee = Fee.from_transaction(tx)
    previous_ledger = previous_ledger(previous_chain)
    ledger_movements = next_ledger(tx, fee, previous_ledger, unspent_outputs)

    node_movements = %NodeMovements{
      fee: fee,
      rewards:
        Reward.distribute_fee(
          fee,
          welcome_node,
          coordinator_node,
          cross_validation_nodes,
          previous_storage_nodes
        )
    }

    ValidationStamp.new(
      reduce_proof_of_work_result(pow_result),
      ProofOfIntegrity.from_chain([tx | previous_chain]),
      ledger_movements,
      node_movements
    )
  end

  defp previous_ledger([]) do
    %LedgerMovements{}
  end

  defp previous_ledger([
         %Transaction{validation_stamp: %ValidationStamp{ledger_movements: ledger_movements}}
       ]) do
    ledger_movements
  end

  defp next_ledger(tx = %Transaction{}, fee, previous_ledger, unspent_outputs) do
    case UTXO.next_ledger(tx, fee, previous_ledger, unspent_outputs) do
      {:ok, ledger} ->
        ledger

      _ ->
        previous_ledger
    end
  end

  defp reduce_proof_of_work_result({:ok, pow}) do
    pow
  end

  defp reduce_proof_of_work_result({:error, :not_found}) do
    ""
  end

  @doc """
  Validate a validation stamp and return a list of inconsistencies when subsets checks are invalid

  Each subset verification is run independently and concurrently and aggregated together to produce a list of inconsistencies
  """
  @spec check_validation_stamp(
          Transaction.pending(),
          ValidationStamp.t(),
          binary(),
          list(binary()),
          list(Transaction.validated()),
          list(Transaction.validated())
        ) :: :ok | {:error, list(atom)}
  def check_validation_stamp(
        tx = %Transaction{},
        stamp = %ValidationStamp{
          proof_of_work: pow,
          proof_of_integrity: poi,
          ledger_movements: next_ledger,
          node_movements: %NodeMovements{fee: fee, rewards: rewards}
        },
        coordinator_public_key,
        validation_nodes,
        previous_chain,
        unspent_outputs
      ) do
    [
      fn -> check_validation_stamp_signature(stamp, coordinator_public_key) end,
      fn ->
        if ProofOfWork.verify(tx, pow) do
          :ok
        else
          {:error, :invalid_proof_of_work}
        end
      end,
      fn -> check_validation_stamp_proof_of_integrity([tx | previous_chain], poi) end,
      fn -> check_validation_stamp_fee(tx, fee) end,
      fn ->
        check_validation_stamp_ledger_movements(
          tx,
          previous_ledger(previous_chain),
          unspent_outputs,
          next_ledger
        )
      end,
      fn -> check_validation_stamp_rewards(tx, validation_nodes, rewards) end
    ]
    |> Task.async_stream(& &1.())
    |> Enum.into([], fn {:ok, res} -> res end)
    |> Enum.reject(fn res -> match?(:ok, res) end)
    |> case do
      [] ->
        :ok

      inconsistencies ->
        {:error, Enum.map(inconsistencies, fn {_, reason} -> reason end)}
    end
  end

  @doc """
  Verify the stamp signature from the coordinator public key

  ## Examples

     iex> pub = UnirisCrypto.last_node_public_key()
     iex> UnirisChain.Transaction.ValidationStamp.new(
     ...>   :crypto.strong_rand_bytes(32),
     ...>   :crypto.strong_rand_bytes(32),
     ...>   %UnirisChain.Transaction.ValidationStamp.LedgerMovements{},
     ...>   %UnirisChain.Transaction.ValidationStamp.NodeMovements{
     ...>     fee: 1.0,
     ...>     rewards: [{:crypto.strong_rand_bytes(32), 1}]
     ...>   }
     ...> )
     ...> |> UnirisValidation.DefaultImpl.Stamp.check_validation_stamp_signature(pub)
     :ok
  """
  def check_validation_stamp_signature(stamp = %ValidationStamp{}, coordinator_public_key) do
    if ValidationStamp.valid_signature?(stamp, coordinator_public_key) do
      :ok
    else
      {:error, :invalid_signature}
    end
  end

  @doc """
  Verifies the stamp's proof of integrity from a given chain of transaction by rebuilding it
  from the previous chain retrieved from the context building.

  ## Examples

     iex> tx = %UnirisChain.Transaction{
     ...>   address: "",
     ...>   type: :transfer,
     ...>   timestamp: DateTime.utc_now(),
     ...>   data: %{},
     ...>   previous_public_key: "",
     ...>   previous_signature: "",
     ...>   origin_signature: ""
     ...> }
     iex> chain = [ %UnirisChain.Transaction{
     ...>   address: "",
     ...>   type: :transfer,
     ...>   timestamp: DateTime.utc_now(),
     ...>   data: %{},
     ...>   previous_public_key: "",
     ...>   previous_signature: "",
     ...>   origin_signature: "",
     ...>   validation_stamp: %UnirisChain.Transaction.ValidationStamp{
     ...>     proof_of_work: :crypto.strong_rand_bytes(32),
     ...>     proof_of_integrity: :crypto.strong_rand_bytes(32),
     ...>     ledger_movements: %UnirisChain.Transaction.ValidationStamp.LedgerMovements{},
     ...>     node_movements: %UnirisChain.Transaction.ValidationStamp.NodeMovements{
     ...>      fee: 1.0,
     ...>      rewards: []
     ...>     },
     ...>     signature: :crypto.strong_rand_bytes(32)
     ...>   }
     ...> }]
     iex> poi = UnirisValidation.DefaultImpl.ProofOfIntegrity.from_chain([tx | chain])
     iex> UnirisValidation.DefaultImpl.Stamp.check_validation_stamp_proof_of_integrity([tx | chain], poi)
     :ok

  """
  def check_validation_stamp_proof_of_integrity(chain, poi) do
    if ProofOfIntegrity.from_chain(chain) == poi do
      :ok
    else
      {:error, :invalid_proof_of_integrity}
    end
  end

  @doc """
  Verify the transaction fee from the validation stamp

  ## Examples

     iex> %UnirisChain.Transaction{
     ...>   address: :crypto.strong_rand_bytes(32),
     ...>   type: :transfer,
     ...>   timestamp: DateTime.utc_now(),
     ...>   data: %{},
     ...>   previous_public_key: :crypto.strong_rand_bytes(32),
     ...>   previous_signature: :crypto.strong_rand_bytes(64),
     ...>   origin_signature: :crypto.strong_rand_bytes(64)
     ...> }
     ...> |> UnirisValidation.DefaultImpl.Stamp.check_validation_stamp_fee(0.1)
     :ok
  """
  def check_validation_stamp_fee(tx = %Transaction{}, fee) do
    if Fee.from_transaction(tx) == fee do
      :ok
    else
      {:error, :invalid_fee}
    end
  end

  @doc """
  Verify the node movements rewards by rebuilding the reward fee distribution with the expected
  previous storage nodes by validators.

  ## Examples

  Returns an error when the node rewarded is an empty list

     iex> %UnirisChain.Transaction{
     ...>   address: :crypto.strong_rand_bytes(32),
     ...>   type: :transfer,
     ...>   timestamp: DateTime.utc_now(),
     ...>   data: %{},
     ...>   previous_public_key: :crypto.strong_rand_bytes(32),
     ...>   previous_signature: :crypto.strong_rand_bytes(64),
     ...>   origin_signature: :crypto.strong_rand_bytes(64)
     ...> }
     ...> |> UnirisValidation.DefaultImpl.Stamp.check_validation_stamp_rewards(["validation_node"], [])
     {:error, :invalid_rewarded_nodes}

  """
  def check_validation_stamp_rewards(_, _, []) do
    {:error, :invalid_rewarded_nodes}
  end

  def check_validation_stamp_rewards(tx = %Transaction{}, validation_node_public_keys, rewards)
      when is_list(rewards) and length(rewards) >= 2 do
    fee = Fee.from_transaction(tx)

    expected_storage_nodes = expected_storage_nodes(tx.previous_public_key)

    [{welcome_node, _}, {coordinator_node, _}] = Enum.take(rewards, 2)

    %{nodes: rewarded_nodes, rewards: rewards} = reduce_rewards(rewards)

    rewarded_storage_nodes =
      rewarded_nodes
      |> Kernel.--([welcome_node])
      |> Kernel.--([coordinator_node])
      |> Kernel.--(validation_node_public_keys)

    if Enum.all?(rewarded_storage_nodes, &(&1 in expected_storage_nodes)) do
      Reward.distribute_fee(
        fee,
        welcome_node,
        coordinator_node,
        validation_node_public_keys,
        rewarded_storage_nodes
      )
      |> Enum.map(fn {_, distribution} -> distribution end)
      |> case do
        distributed_rewards when rewards == distributed_rewards ->
          :ok

        _ ->
          {:error, :invalid_reward_distributions}
      end
    else
      {:error, :invalid_rewarded_nodes}
    end
  end

  @doc """
  Verify the ledger movement from the validation stamp by rebuilding the UTXO next ledger from context building data such as previous ledger, unspent outputs

  ## Examples

     iex> previous_ledger = %UnirisChain.Transaction.ValidationStamp.LedgerMovements{
     ...>  uco: %UnirisChain.Transaction.ValidationStamp.LedgerMovements.UTXO{},
     ...>  nft: %UnirisChain.Transaction.ValidationStamp.LedgerMovements.UTXO{}
     ...> }
     iex> tx = %UnirisChain.Transaction{
     ...>   address: :crypto.strong_rand_bytes(32),
     ...>   type: :transfer,
     ...>   timestamp: DateTime.utc_now(),
     ...>   data: %{
     ...>     ledger: %{
     ...>       uco: %{
     ...>         transfers: [%{to: :crypto.strong_rand_bytes(32), amount: 5}]
     ...>       }
     ...>     }
     ...>   },
     ...>   previous_public_key: "",
     ...>   previous_signature: "",
     ...>   origin_signature: ""
     ...> }
     iex> unspent_outputs = [
     ...>   %UnirisChain.Transaction{
     ...>   address: :crypto.strong_rand_bytes(32),
     ...>   type: :transfer,
     ...>   timestamp: DateTime.utc_now(),
     ...>   data: %{
     ...>     ledger: %{
     ...>       uco: %{
     ...>         transfers: [%{to: tx.address, amount: 10}]
     ...>       }
     ...>     }
     ...>   },
     ...>   previous_public_key: "",
     ...>   previous_signature: "",
     ...>   origin_signature: ""
     ...> }]
     iex> {:ok, next_ledger} = UnirisValidation.DefaultImpl.UTXO.next_ledger(tx, 0.1, previous_ledger, unspent_outputs)
     iex> UnirisValidation.DefaultImpl.Stamp.check_validation_stamp_ledger_movements(tx, previous_ledger, unspent_outputs, next_ledger)
     :ok
  """
  def check_validation_stamp_ledger_movements(
        tx = %Transaction{},
        previous_ledger = %LedgerMovements{},
        unspent_outputs,
        next_ledger = %LedgerMovements{}
      ) do
    fee = Fee.from_transaction(tx)

    case UTXO.next_ledger(tx, fee, previous_ledger, unspent_outputs) do
      {:ok, expected_next_ledger = %LedgerMovements{}} when expected_next_ledger == next_ledger ->
        :ok

      _ ->
        {:error, :invalid_ledger_movements}
    end
  end

  defp expected_storage_nodes(previous_public_key) do
    previous_public_key
    |> Crypto.hash()
    |> Election.storage_nodes(Network.list_nodes(), Network.storage_nonce())
    |> Enum.map(& &1.last_public_key)
  end

  defp reduce_rewards(rewards) do
    Enum.reduce(rewards, %{nodes: [], rewards: []}, fn {key, reward}, acc ->
      acc
      |> Map.update!(:nodes, &(&1 ++ [key]))
      |> Map.update!(:rewards, &(&1 ++ [reward]))
    end)
  end

  @doc """
  Create a cross validation stamp by signing either the validation stamp or inconsistencies if any.

  ## Examples

     iex> UnirisCrypto.generate_deterministic_keypair("seed", persistence: true)
     iex> stamp = %UnirisChain.Transaction.ValidationStamp{
     ...>  proof_of_work: "A9BCEB532873BAB3BDF5DD41594CC57CE0AC5E1073B50F4CE3FA6DDF4F3DD2F1",
     ...>  proof_of_integrity: "239CCBB96728772F42C5DC3E1AC236208CDA2E8AAD3EF0FF8838081A7AFD4AF9",
     ...>  ledger_movements: %UnirisChain.Transaction.ValidationStamp.LedgerMovements{},
     ...>  node_movements: %UnirisChain.Transaction.ValidationStamp.NodeMovements{
     ...>     fee: 0.1,
     ...>     rewards: []
     ...>  },
     ...>  signature: "D8DCCFFDF472DBCA8C1DA0D819A77BEF34A4804D3576791FB3490678C2B3FBCBBC10EB997B35523998B20C2C802AA38DD9A9BBD365E52434DED76137A6611777"
     ...> }
     iex> UnirisValidation.DefaultImpl.Stamp.create_cross_validation_stamp(stamp, [])
     {<<104, 30, 64, 135, 105, 68, 240, 9, 38, 116, 10, 193, 134, 181, 253, 138, 251,
     202, 78, 185, 100, 6, 94, 55, 158, 58, 83, 23, 2, 15, 161, 248, 44, 27, 198,
     104, 83, 201, 59, 131, 81, 234, 240, 77, 55, 214, 178, 22, 237, 206, 18, 9,
     87, 66, 228, 63, 94, 181, 0, 93, 152, 239, 4, 8>>, []}
  """
  def create_cross_validation_stamp(stamp = %ValidationStamp{}, []) do
    sig = Crypto.sign(stamp, with: :node, as: :last)
    {sig, []}
  end

  def create_cross_validation_stamp(_stamp, inconsistencies) do
    sig = Crypto.sign(inconsistencies, with: :node, as: :last)
    {sig, inconsistencies}
  end

  @doc """
  Verify the integrity of the a cross validation stamp by checking its signature according to the stamp or inconsistencies if any

  ## Examples

     iex> pub = UnirisCrypto.generate_deterministic_keypair("seed", persistence: true)
     iex> stamp = %UnirisChain.Transaction.ValidationStamp{
     ...>   proof_of_work: :crypto.strong_rand_bytes(32),
     ...>   proof_of_integrity: :crypto.strong_rand_bytes(32),
     ...>   ledger_movements: %UnirisChain.Transaction.ValidationStamp.LedgerMovements{},
     ...>   node_movements: %UnirisChain.Transaction.ValidationStamp.NodeMovements{
     ...>     fee: 0.1,
     ...>     rewards: []
     ...>   },
     ...>   signature: :crypto.strong_rand_bytes(32)
     ...> }
     iex> cross_validation_stamp = UnirisValidation.DefaultImpl.Stamp.create_cross_validation_stamp(stamp, [])
     iex> UnirisValidation.DefaultImpl.Stamp.valid_cross_validation_stamp?(
     ...>  cross_validation_stamp,
     ...>  stamp,
     ...>  pub
     ...> )
     true
  """
  @spec valid_cross_validation_stamp?(
          Transaction.cross_validation_stamp(),
          ValidationStamp.t(),
          binary()
        ) :: boolean()
  def valid_cross_validation_stamp?(
        {signature, inconsistencies},
        stamp = %ValidationStamp{},
        node_public_key
      ) do
    case inconsistencies do
      [] ->
        Crypto.verify(signature, stamp, node_public_key)

      _ ->
        Crypto.verify(signature, inconsistencies, node_public_key)
    end
  end

  @doc """
  Verify if all the cross validation stamps are valid
  """
  @spec valid_cross_validation_stamps?(
          list(Transaction.cross_validation_stamp()),
          ValidationStamp.t()
        ) :: boolean
  def valid_cross_validation_stamps?(cross_stamps, stamp = %ValidationStamp{}) do
    Enum.all?(cross_stamps, fn {sig, inconsistencies, pub} ->
      valid_cross_validation_stamp?({sig, inconsistencies}, stamp, pub)
    end)
  end
end
