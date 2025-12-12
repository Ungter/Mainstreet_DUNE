WITH parameters AS (
    SELECT
        -- Sonic Token Address (Original/History)
        0xE5Fb2Ed6832deF99ddE57C0b9d9A56537C89121D AS sonic_token_address,
        
        -- Ethereum Token Address 
        0x4ba01f22827018b4772CD326C7627FB4956A7C00 AS eth_token_address,

        18 AS token_decimals,
        0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef AS transfer_topic,
        0x0000000000000000000000000000000000000000000000000000000000000000 AS zero_topic
),

sonic_history AS (
    -- Calculate Sonic Supply from Sonic Logs (Preserves History)
    SELECT
        date_trunc('day', block_time) AS day,
        SUM(
            CASE
                WHEN topic1 = (SELECT zero_topic FROM parameters) THEN CAST(varbinary_to_uint256(data) AS DOUBLE) -- Mint
                WHEN topic2 = (SELECT zero_topic FROM parameters) THEN -CAST(varbinary_to_uint256(data) AS DOUBLE) -- Burn
                ELSE 0
            END
        ) AS sonic_net_change
    FROM sonic.logs
    WHERE contract_address = (SELECT sonic_token_address FROM parameters)
      AND topic0 = (SELECT transfer_topic FROM parameters)
    GROUP BY 1
),

eth_activity AS (
    -- Calculate ETH Supply & Bridge Locking
    SELECT
        date_trunc('day', block_time) AS day,
        
        -- A. Total ETH Existence (Mints - Burns)
        SUM(
            CASE
                WHEN topic1 = (SELECT zero_topic FROM parameters) THEN CAST(varbinary_to_uint256(data) AS DOUBLE)
                WHEN topic2 = (SELECT zero_topic FROM parameters) THEN -CAST(varbinary_to_uint256(data) AS DOUBLE)
                ELSE 0
            END
        ) AS eth_total_change,

        -- B. Locked in Bridge (Transfers In/Out of Contract)
        SUM(
            CASE
                -- Locked (Transfer TO Contract)
                WHEN SUBSTR(topic2, 13, 20) = (SELECT eth_token_address FROM parameters)
                THEN CAST(varbinary_to_uint256(data) AS DOUBLE)
                
                -- Unlocked (Transfer FROM Contract)
                WHEN SUBSTR(topic1, 13, 20) = (SELECT eth_token_address FROM parameters)
                THEN -CAST(varbinary_to_uint256(data) AS DOUBLE)
                
                ELSE 0
            END
        ) AS eth_bridge_lock_change
    FROM ethereum.logs
    WHERE contract_address = (SELECT eth_token_address FROM parameters)
      AND topic0 = (SELECT transfer_topic FROM parameters)
    GROUP BY 1
),

combined_timeline AS (
    -- Combine dates from both chains so no days are missing
    SELECT day FROM sonic_history
    UNION
    SELECT day FROM eth_activity
),

final_aggregation AS (
    SELECT
        t.day,
        -- Sum changes for Sonic
        COALESCE(s.sonic_net_change, 0) AS sonic_change,
        -- Sum changes for ETH
        COALESCE(e.eth_total_change, 0) AS eth_total_change,
        COALESCE(e.eth_bridge_lock_change, 0) AS eth_locked_change
    FROM combined_timeline t
    LEFT JOIN sonic_history s ON t.day = s.day
    LEFT JOIN eth_activity e ON t.day = e.day
)

SELECT
    day,
    
    -- 1. Sonic Supply (Cumulative from Sonic Logs)
    SUM(sonic_change) OVER (ORDER BY day) / power(10, (SELECT token_decimals FROM parameters)) AS sonic_supply,

    -- 2. Native ETH Supply (Total ETH Minted - Amount Locked in Bridge)
    (SUM(eth_total_change) OVER (ORDER BY day) - SUM(eth_locked_change) OVER (ORDER BY day)) 
    / power(10, (SELECT token_decimals FROM parameters)) AS native_eth_supply,

    SUM(sonic_change + eth_total_change - eth_locked_change) OVER (ORDER BY day) / power(10, (SELECT token_decimals FROM parameters)) AS aum

FROM final_aggregation
ORDER BY day DESC;
