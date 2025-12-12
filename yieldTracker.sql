WITH sonic_data AS (
    SELECT 
        day, 
        total_rewards_paid AS rewards_sonic
    FROM query_5789997
),

eth_data AS (
    SELECT 
        day, 
        total_rewards_paid AS rewards_eth
    FROM query_6173087
),

combined_days AS (
    SELECT day FROM sonic_data
    UNION
    SELECT day FROM eth_data
)

SELECT
    c.day,
    COALESCE(s.rewards_sonic, 0) AS sonic_rewards_paid,
    COALESCE(e.rewards_eth, 0) AS eth_rewards_paid,
    (COALESCE(s.rewards_sonic, 0) + COALESCE(e.rewards_eth, 0)) AS global_rewards_paid
FROM combined_days c
LEFT JOIN sonic_data s ON c.day = s.day
LEFT JOIN eth_data e ON c.day = e.day
ORDER BY c.day DESC;
