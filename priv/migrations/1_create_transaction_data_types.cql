CREATE TYPE IF NOT EXISTS archethic.uco_transfer(
  "to" blob,
  amount bigint
);

CREATE TYPE IF NOT EXISTS archethic.uco_ledger(
  transfers LIST<frozen<uco_transfer>>
);

CREATE TYPE IF NOT EXISTS archethic.nft_transfer(
  "to" blob,
  amount bigint,
  nft blob
);

CREATE TYPE IF NOT EXISTS archethic.nft_ledger(
  transfers LIST<frozen<nft_transfer>>
);

CREATE TYPE IF NOT EXISTS archethic.ownership(
  authorized_keys MAP<blob, blob>,
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
  ownerships LIST<frozen<ownership>>
);
