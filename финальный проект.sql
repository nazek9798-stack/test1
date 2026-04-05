Select * from customers;
Select * from transactions;

SELECT 
    ID_client,
    AVG(Sum_payment) AS avg_check,                      
    SUM(Sum_payment) / 12 AS avg_monthly_payment,       
    COUNT(Id_check) AS total_operations                
FROM transactions
WHERE date_new >= '2015-06-01' AND date_new < '2016-06-01'
GROUP BY ID_client
HAVING COUNT(DISTINCT FORMAT(date_new, 'yyyy-MM')) = 12;

SELECT 
    DATE_FORMAT(date_new, '%Y-%m') AS month_period,    
    AVG(Sum_payment) AS avg_check_month,             
    COUNT(Id_check) AS ops_count_month,               
    COUNT(DISTINCT ID_client) AS clients_count_month, 
    SUM(Sum_payment) AS total_sum_month               
FROM transactions
WHERE date_new >= '2015-06-01' AND date_new < '2016-06-01'
GROUP BY month_period
ORDER BY month_period;

WITH MonthlyData AS (
    SELECT 
        DATE_FORMAT(t.date_new, '%Y-%m') AS month_period,
        COUNT(t.Id_check) AS count_ops,
        SUM(t.Sum_payment) AS sum_payment,
        COUNT(DISTINCT t.ID_client) AS count_clients,
        -- Считаем количество операций и суммы по каждому полу внутри месяца
        COUNT(CASE WHEN c.Gender = 'M' THEN 1 END) AS ops_m,
        COUNT(CASE WHEN c.Gender = 'F' THEN 1 END) AS ops_f,
        COUNT(CASE WHEN c.Gender IS NULL OR c.Gender = '' THEN 1 END) AS ops_na,
        SUM(CASE WHEN c.Gender = 'M' THEN t.Sum_payment ELSE 0 END) AS sum_m,
        SUM(CASE WHEN c.Gender = 'F' THEN t.Sum_payment ELSE 0 END) AS sum_f,
        SUM(CASE WHEN c.Gender IS NULL OR c.Gender = '' THEN t.Sum_payment ELSE 0 END) AS sum_na
    FROM transactions t
    LEFT JOIN customers c ON t.ID_client = c.ID_client
    WHERE t.date_new >= '2015-06-01' AND t.date_new < '2016-06-01'
    GROUP BY month_period
),
YearlyTotal AS (
    -- Шаг 2: Считаем общие итоги за год для вычисления долей
    SELECT 
        SUM(count_ops) AS year_total_ops,
        SUM(sum_payment) AS year_total_sum
    FROM MonthlyData
)
SELECT 
    m.month_period,
    -- 1. Средние показатели в месяц
    (m.sum_payment / m.count_ops) AS avg_check,
    m.count_ops AS ops_in_month,
    m.count_clients AS clients_in_month,
    
    -- 2. Доли от годовых показателей
    ROUND(m.count_ops * 100.0 / y.year_total_ops, 2) AS share_ops_year_pct,
    ROUND(m.sum_payment * 100.0 / y.year_total_sum, 2) AS share_sum_year_pct,
    
    -- 3. Соотношение M/F/NA (по количеству клиентов/операций)
    ROUND(m.ops_m * 100.0 / m.count_ops, 2) AS male_ops_pct,
    ROUND(m.ops_f * 100.0 / m.count_ops, 2) AS female_ops_pct,
    ROUND(m.ops_na * 100.0 / m.count_ops, 2) AS na_ops_pct,
    
    -- 4. Доля затрат по полу внутри месяца
    ROUND(m.sum_m * 100.0 / m.sum_payment, 2) AS male_spending_pct,
    ROUND(m.sum_f * 100.0 / m.sum_payment, 2) AS female_spending_pct,
    ROUND(m.sum_na * 100.0 / m.sum_payment, 2) AS na_spending_pct
FROM MonthlyData m
CROSS JOIN YearlyTotal y
ORDER BY m.month_period;


WITH client_ages AS (
    -- Определяем возрастную группу для каждого клиента
    SELECT 
        c.ID_client,
        c.Gender,
        CASE 
            WHEN c.Age IS NULL THEN 'Unknown'
            ELSE CONCAT(FLOOR(c.Age / 10) * 10, '-', FLOOR(c.Age / 10) * 10 + 9)
        END AS age_group
    FROM customers c
),
base_data AS (
    -- Соединяем транзакции с возрастными группами
    SELECT 
        t.Id_check,
        t.Sum_payment,
        t.date_new,
        ca.age_group,
        CONCAT(YEAR(t.date_new), '-Q', QUARTER(t.date_new)) AS quarter_period
    FROM transactions t
    LEFT JOIN client_ages ca ON t.ID_client = ca.ID_client
    WHERE t.date_new >= '2015-06-01' AND t.date_new < '2016-06-01'
),
quarterly_stats AS (
    -- Считаем показатели по кварталам и возрастным группам
    SELECT 
        quarter_period,
        age_group,
        SUM(Sum_payment) AS q_sum,
        COUNT(Id_check) AS q_ops,
        AVG(Sum_payment) AS q_avg_check
    FROM base_data
    GROUP BY quarter_period, age_group
),
total_per_quarter AS (
    -- Итоги по кварталам для расчета %
    SELECT 
        quarter_period,
        SUM(q_sum) AS total_q_sum,
        SUM(q_ops) AS total_q_ops
    FROM quarterly_stats
    GROUP BY quarter_period
)

-- Финальный вывод: общие показатели + поквартальные
SELECT 
    qs.quarter_period,
    qs.age_group,
    qs.q_sum AS total_sum,
    qs.q_ops AS count_ops,
    ROUND(qs.q_avg_check, 2) AS avg_check,
    -- % суммы внутри квартала
    ROUND(qs.q_sum * 100.0 / tpq.total_q_sum, 2) AS pct_sum_in_quarter,
    -- % операций внутри квартала
    ROUND(qs.q_ops * 100.0 / tpq.total_q_ops, 2) AS pct_ops_in_quarter
FROM quarterly_stats qs
JOIN total_per_quarter tpq ON qs.quarter_period = tpq.quarter_period
ORDER BY qs.quarter_period, qs.age_group;