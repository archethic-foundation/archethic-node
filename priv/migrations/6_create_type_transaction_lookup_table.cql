CREATE TABLE IF NOT EXISTS archethic.transaction_type_lookup(
  type varchar,
  address blob,
  timestamp timestamp,
  PRIMARY KEY (type, timestamp)
) WITH CLUSTERING ORDER BY (timestamp DESC);
