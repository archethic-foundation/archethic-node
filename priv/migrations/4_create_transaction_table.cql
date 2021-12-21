CREATE TABLE IF NOT EXISTS archethic.transactions (
  version int,
  address blob PRIMARY KEY,
  type varchar,
  data frozen<pending_transaction_data>,
  previous_public_key blob,
  previous_signature blob,
  origin_signature blob,
  validation_stamp frozen<validation_stamp>,
  cross_validation_stamps LIST<frozen<cross_validation_stamp>>
) 
WITH COMPRESSION = { 'sstable_compression': 'LZ4Compressor' };
