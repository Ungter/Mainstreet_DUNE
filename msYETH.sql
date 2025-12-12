WITH parameters AS (
  SELECT
    0x890A5122Aa1dA30fEC4286DE7904Ff808F0bd74A AS vault_address, -- msY
    0x4ba01f22827018b4772CD326C7627FB4956A7C00 AS asset_address, -- msUSD
    18 AS asset_decimals
),

asset_balance_changes AS (
  SELECT
    date_trunc('day', l.block_time) AS day,
    SUM(
      CASE
        -- inflow to vault
        WHEN l.topic2 = concat(from_hex('000000000000000000000000'), p.vault_address)
          THEN CAST(bytearray_to_uint256(l.data) AS DECIMAL(38, 0))
        -- outflow from vault
        WHEN l.topic1 = concat(from_hex('000000000000000000000000'), p.vault_address)
          THEN -CAST(bytearray_to_uint256(l.data) AS DECIMAL(38, 0))
        ELSE CAST(0 AS DECIMAL(38, 0))
      END
    ) AS net_change
  FROM ethereum.logs l
  CROSS JOIN parameters p
  WHERE l.contract_address = p.asset_address
    AND l.topic0 = 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
  GROUP BY 1
),

-- Track Rewards (Mints to Vault)
rewards_changes AS (
  SELECT
    date_trunc('day', l.block_time) AS day,
    SUM(CAST(bytearray_to_uint256(l.data) AS DECIMAL(38, 0))) AS reward_amount
  FROM ethereum.logs l
  CROSS JOIN parameters p
  WHERE l.contract_address = p.asset_address -- msUSD Token
    AND l.topic0 = 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
    -- Filter: From 0x0 (Mint) AND To Vault
    AND l.topic1 = 0x0000000000000000000000000000000000000000000000000000000000000000
    AND l.topic2 = concat(from_hex('000000000000000000000000'), p.vault_address)
  GROUP BY 1
),

share_supply_changes AS (
  SELECT
    date_trunc('day', l.block_time) AS day,
    SUM(
      CASE
        WHEN l.topic1 = 0x0000000000000000000000000000000000000000000000000000000000000000
          THEN CAST(bytearray_to_uint256(l.data) AS DECIMAL(38, 0))
        WHEN l.topic2 = 0x0000000000000000000000000000000000000000000000000000000000000000
          THEN -CAST(bytearray_to_uint256(l.data) AS DECIMAL(38, 0))
        ELSE CAST(0 AS DECIMAL(38, 0))
      END
    ) AS net_change
  FROM ethereum.logs l
  CROSS JOIN parameters p
  WHERE l.contract_address = p.vault_address
    AND l.topic0 = 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef
  GROUP BY 1
),

all_days AS (
  SELECT day FROM asset_balance_changes
  UNION
  SELECT day FROM share_supply_changes
  UNION
  SELECT day FROM rewards_changes
),

daily_balances AS (
  SELECT
    d.day,
    -- Total Assets
    SUM(COALESCE(abc.net_change, CAST(0 AS DECIMAL(38, 0)))) OVER (
      ORDER BY d.day ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) / CAST(power(10, p.asset_decimals) AS DOUBLE) AS total_assets,
    
    -- Total Supply
    SUM(COALESCE(ssc.net_change, CAST(0 AS DECIMAL(38, 0)))) OVER (
      ORDER BY d.day ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) / CAST(power(10, p.asset_decimals) AS DOUBLE) AS total_supply,

    -- Cumulative Rewards
    SUM(COALESCE(r.reward_amount, CAST(0 AS DECIMAL(38, 0)))) OVER (
      ORDER BY d.day ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) / CAST(power(10, p.asset_decimals) AS DOUBLE) AS total_rewards_paid

  FROM all_days d
  LEFT JOIN asset_balance_changes abc ON d.day = abc.day
  LEFT JOIN share_supply_changes ssc ON d.day = ssc.day
  LEFT JOIN rewards_changes r ON d.day = r.day
  CROSS JOIN parameters p
)

SELECT
  day,
  total_assets,
  total_supply,
  total_rewards_paid,
  CASE WHEN total_supply > 0 THEN total_assets / total_supply ELSE 0 END AS price_per_share
FROM daily_balances
ORDER BY day DESC;
