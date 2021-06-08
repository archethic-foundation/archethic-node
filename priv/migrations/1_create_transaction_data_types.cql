CREATE TYPE IF NOT EXISTS uniris.uco_transfer(
  "to" blob,
  amount double
);

CREATE TYPE IF NOT EXISTS uniris.uco_ledger(
  transfers LIST<frozen<uco_transfer>>
);

CREATE TYPE IF NOT EXISTS uniris.nft_transfer(
  "to" blob,
  amount double,
  nft blob
);

CREATE TYPE IF NOT EXISTS uniris.nft_ledger(
  transfers LIST<frozen<nft_transfer>>
);

CREATE TYPE IF NOT EXISTS uniris.pending_transaction_data_keys(
  authorized_keys map<blob, blob>,
  secret blob
);

CREATE TYPE IF NOT EXISTS uniris.pending_transaction_ledger(
  uco frozen<uco_ledger>,
  nft frozen<nft_ledger>
);

CREATE TYPE IF NOT EXISTS uniris.pending_transaction_data(
  code text,
  content blob,
  recipients LIST<blob>,
  ledger frozen<pending_transaction_ledger>,
  keys frozen<pending_transaction_data_keys>
);
