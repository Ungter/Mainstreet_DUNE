WITH parameters AS (
    SELECT
        0xe5fb2ed6832def99dde57c0b9d9a56537c89121d AS msUSD_sonic_address, 
        0xc7990369da608c2f4903715e3bd22f2970536c29 AS smsUSD_sonic_address, 
        
        0x890A5122Aa1dA30fEC4286DE7904Ff808F0bd74A AS msY_eth_vault_address, 
        0x4ba01f22827018b4772CD326C7627FB4956A7C00 AS msUSD_eth_token_address,

        18 AS msUSD_decimals,
        0xddf252ad1be2c89b69c2b068fc378daa952ba7f163c4a11628f55a4df523b3ef AS transfer_topic
),

-- 1. IMPORT SUPPLY 
imported_supply_data AS (
    SELECT
        native_eth_supply,
        sonic_supply
    FROM 
        query_6173272
    ORDER BY 
        day DESC
    LIMIT 1
),

-- 2. SONIC: smsUSD Balance
vault_balance_smsUSD AS (
    SELECT
        COALESCE(SUM(
            CASE
                WHEN topic2 = FROM_HEX(CONCAT('000000000000000000000000', SUBSTRING(CAST((SELECT smsUSD_sonic_address FROM parameters) AS VARCHAR), 3))) 
                THEN CAST(varbinary_to_uint256(data) AS DOUBLE)
                WHEN topic1 = FROM_HEX(CONCAT('000000000000000000000000', SUBSTRING(CAST((SELECT smsUSD_sonic_address FROM parameters) AS VARCHAR), 3))) 
                THEN -CAST(varbinary_to_uint256(data) AS DOUBLE)
                ELSE 0
            END
        ), 0) / power(10, (SELECT msUSD_decimals FROM parameters)) AS balance
    FROM
        sonic.logs
    WHERE
        contract_address = (SELECT msUSD_sonic_address FROM parameters)
        AND topic0 = (SELECT transfer_topic FROM parameters)
),

-- 3. ETHEREUM: msY Balance
vault_balance_msY_eth AS (
    SELECT
        COALESCE(SUM(
            CASE
                WHEN SUBSTR(topic2, 13, 20) = (SELECT msY_eth_vault_address FROM parameters) 
                THEN CAST(varbinary_to_uint256(data) AS DOUBLE)
                WHEN SUBSTR(topic1, 13, 20) = (SELECT msY_eth_vault_address FROM parameters) 
                THEN -CAST(varbinary_to_uint256(data) AS DOUBLE)
                ELSE 0
            END
        ), 0) / power(10, (SELECT msUSD_decimals FROM parameters)) AS balance
    FROM
        ethereum.logs
    WHERE
        contract_address = (SELECT msUSD_eth_token_address FROM parameters)
        AND topic0 = (SELECT transfer_topic FROM parameters)
)

SELECT
    -- Balances
    s.balance AS msUSD_in_smsUSD_vault,
    y.balance AS msUSD_in_msY_vault,
    
    -- Supply
    (imp.native_eth_supply + imp.sonic_supply) AS global_total_supply,
    imp.native_eth_supply,
    imp.sonic_supply,
    
    -- Staking Ratios
    (s.balance / (imp.native_eth_supply + imp.sonic_supply)) * 100 AS percent_staked_in_smsUSD,
    
    (y.balance / (imp.native_eth_supply + imp.sonic_supply)) * 100 AS percent_staked_in_msY

FROM
    vault_balance_smsUSD s
CROSS JOIN
    vault_balance_msY_eth y
CROSS JOIN
    imported_supply_data imp;
