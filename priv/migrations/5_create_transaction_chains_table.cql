CREATE TABLE IF NOT EXISTS archethic.transaction_chains(
    chain_address blob,
    transaction_address blob,
    transaction_timestamp timestamp,
    PRIMARY KEY (chain_address, transaction_timestamp)
)
WITH CLUSTERING ORDER BY (transaction_timestamp DESC)
AND COMPRESSION = { 'sstable_compression': 'LZ4Compressor' };
