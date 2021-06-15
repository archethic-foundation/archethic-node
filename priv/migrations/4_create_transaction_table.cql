CREATE TABLE IF NOT EXISTS uniris.transactions (
  chain_address blob,
  bucket int,
  timestamp timestamp,
  version int,
  address blob,
  type varchar,
  data frozen<pending_transaction_data>,
  previous_public_key blob,
  previous_signature blob,
  origin_signature blob,
  validation_stamp frozen<validation_stamp>,
  cross_validation_stamps LIST<frozen<cross_validation_stamp>>,
  PRIMARY KEY (chain_address, bucket, timestamp)
) 
WITH CLUSTERING ORDER BY (bucket DESC, timestamp DESC)
AND COMPRESSION = { 'sstable_compression': 'LZ4Compressor' };
