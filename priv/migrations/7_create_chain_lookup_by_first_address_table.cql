CREATE TABLE IF NOT EXISTS uniris.chain_lookup_by_first_address(
  last_transaction_address blob,
  genesis_transaction_address blob,
  PRIMARY KEY (last_transaction_address)
);
