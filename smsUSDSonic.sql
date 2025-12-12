WITH parameters AS (
  SELECT
    0xc7990369da608c2f4903715e3bd22f2970536c29 AS vault_address, -- smsUSD
    0xe5fb2ed6832def99dde57c0b9d9a56537c89121d AS asset_address, -- msUSD
    
    -- Temp yield payer
    0x19F63Dda10b162F0a35c3018ef3710606273D8E3 AS yield_payer_address,
    
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
  FROM sonic.logs l
  CROSS JOIN parameters p
  WHERE l.contract_address = p.asset_address
    AND l.topic0 = 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef -- Transfer
  GROUP BY 1
),

-- Track Rewards
rewards_changes AS (
  SELECT
    date_trunc('day', l.block_time) AS day,
    SUM(CAST(bytearray_to_uint256(l.data) AS DECIMAL(38, 0))) AS reward_amount
  FROM sonic.logs l
  CROSS JOIN parameters p
  WHERE l.contract_address = p.asset_address -- msUSD Token
    AND l.topic0 = 0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef -- Transfer
    
    -- Must be TO the Vault
    AND l.topic2 = concat(from_hex('000000000000000000000000'), p.vault_address)
    
    -- AND coming from either 0x0 OR the Yield Payer
    AND (
        l.topic1 = 0x0000000000000000000000000000000000000000000000000000000000000000
        OR 
        l.topic1 = concat(from_hex('000000000000000000000000'), p.yield_payer_address)
    )
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
  FROM sonic.logs l
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
    -- Total Assets (AUM)
    SUM(COALESCE(abc.net_change, CAST(0 AS DECIMAL(38, 0)))) OVER (
      ORDER BY d.day ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) / CAST(power(10, p.asset_decimals) AS DOUBLE) AS total_assets,
    
    -- Total Supply (Shares)
    SUM(COALESCE(ssc.net_change, CAST(0 AS DECIMAL(38, 0)))) OVER (
      ORDER BY d.day ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
    ) / CAST(power(10, p.asset_decimals) AS DOUBLE) AS total_supply,

    -- Cumulative Rewards Paid
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
