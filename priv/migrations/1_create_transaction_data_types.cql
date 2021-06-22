CREATE TYPE IF NOT EXISTS archethic.uco_transfer(
  "to" blob,
  amount double
);

CREATE TYPE IF NOT EXISTS archethic.uco_ledger(
  transfers LIST<frozen<uco_transfer>>
);

CREATE TYPE IF NOT EXISTS archethic.nft_transfer(
  "to" blob,
  amount double,
  nft blob
);

CREATE TYPE IF NOT EXISTS archethic.nft_ledger(
  transfers LIST<frozen<nft_transfer>>
);

CREATE TYPE IF NOT EXISTS archethic.pending_transaction_data_keys(
  authorized_keys map<blob, blob>,
  secret blob
);

CREATE TYPE IF NOT EXISTS archethic.pending_transaction_ledger(
  uco frozen<uco_ledger>,
  nft frozen<nft_ledger>
);

CREATE TYPE IF NOT EXISTS archethic.pending_transaction_data(
  code text,
  content blob,
  recipients LIST<blob>,
  ledger frozen<pending_transaction_ledger>,
  keys frozen<pending_transaction_data_keys>
);
