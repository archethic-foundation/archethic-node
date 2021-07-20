CREATE TABLE archethic.p2p_summary_by_node(
  node_public_key blob,
  date timestamp,
  available boolean,
  average_availability float,
  PRIMARY KEY(node_public_key, date)
) WITH CLUSTERING ORDER BY (date DESC);
