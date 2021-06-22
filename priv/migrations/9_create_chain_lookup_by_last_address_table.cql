CREATE TABLE IF NOT EXISTS archethic.chain_lookup_by_last_address(
  transaction_address blob,
  last_transaction_address blob,
  timestamp timestamp,
  PRIMARY KEY (transaction_address, timestamp)
) WITH CLUSTERING ORDER BY (timestamp DESC);
