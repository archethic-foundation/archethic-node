CREATE TABLE IF NOT EXISTS archethic.transaction_chains(
    chain_address blob,
    bucket tinyint,
    transaction_address blob,
    transaction_timestamp timestamp,
    PRIMARY KEY ((chain_address, bucket), transaction_timestamp)
)
WITH CLUSTERING ORDER BY (transaction_timestamp DESC)
AND COMPRESSION = { 'sstable_compression': 'LZ4Compressor' };