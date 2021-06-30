CREATE TYPE IF NOT EXISTS archethic.ledger_operations_node_movement(
  "to" blob,
  amount double,
  roles list<text>
);

CREATE TYPE IF NOT EXISTS archethic.ledger_operations_transaction_movement(
  "to" blob,
  amount double,
  type varchar,
  nft_address blob
);

CREATE TYPE IF NOT EXISTS archethic.ledger_operations_unspent_output(
  "from" blob,
  amount double,
  type varchar,
  nft_address blob,
  reward boolean
);

CREATE TYPE IF NOT EXISTS archethic.ledger_operations(
  fee float,
  transaction_movements LIST<frozen<ledger_operations_transaction_movement>>,
  node_movements LIST<frozen<ledger_operations_node_movement>>,
  unspent_outputs LIST<frozen<ledger_operations_unspent_output>>
);

CREATE TYPE IF NOT EXISTS archethic.validation_stamp(
  timestamp timestamp,
  proof_of_work blob,
  proof_of_integrity blob,
  proof_of_election blob,
  ledger_operations frozen<ledger_operations>,
  recipients LIST<blob>,
  signature blob
);
