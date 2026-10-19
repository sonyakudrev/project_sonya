/*
    Анализ рынка недвижимости Санкт-Петербурга
    и Ленинградской области
*/



-- Задача 1. Анализ сроков активности объявлений
-- Сравним объявления Санкт-Петербурга и Ленинградской области по срокам экспозиции.
-- Разделим объявления на категории в зависимости от продолжительности размещения
-- и сравним характеристики объектов в каждой категории:
-- стоимость квадратного метра, площадь, количество комнат и балконов,
-- этажность дома и высоту потолков.
-- Это позволит выявить различия между регионами и сегментами рынка.

-- Определим аномальные значения (выбросы) по значению перцентилей:
WITH limits AS (
    SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats     
),
-- Найдём id объявлений, которые не содержат выбросы:
filtered_id AS (
    SELECT id
    FROM real_estate.flats  
    WHERE 
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
            AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
),
-- делаю категоризацию значений и избавляюсь от NULL:
categorized AS (
    SELECT
        CASE
            WHEN f.city_id = '6X8I' THEN 'СПб'
            ELSE 'ЛенОбл'
        END AS city_category,
        CASE
            WHEN a.days_exposition BETWEEN 1 AND 30 THEN 'до месяца'
            WHEN a.days_exposition BETWEEN 31 AND 90 THEN 'до трех месяцев'
            WHEN a.days_exposition BETWEEN 91 AND 180 THEN 'до полугода'
            WHEN a.days_exposition >= 181 THEN 'более полугода'
        END AS exposition_category,
        ROUND((a.last_price / f.total_area)::numeric, 2) AS price_per_sqm,
        f.total_area,
        f.rooms,
        f.balcony,
        f.floors_total,
        f.ceiling_height
    FROM real_estate.flats AS f
    JOIN real_estate.advertisement AS a
        ON f.id = a.id
    JOIN real_estate.type AS t
        ON f.type_id = t.type_id
    WHERE f.id IN (SELECT id FROM filtered_id)
      AND t.type = 'город'
      AND f.total_area IS NOT NULL
      AND a.last_price IS NOT NULL
      AND a.days_exposition IS NOT NULL
) --основной запрос: 
SELECT
    city_category AS "Регион",
    exposition_category AS "Сегмент активности",
    COUNT(*) AS "Кол-во объявлений",
    ROUND(100.0 * COUNT(*) / SUM(COUNT(*)) OVER (PARTITION BY city_category), 2) AS "Доля объявлений, %",
    ROUND(AVG(price_per_sqm)::numeric, 2) AS "Средняя стоимость кв. метра",
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY price_per_sqm) AS "Медиана стоимости кв. метра",
    ROUND(AVG(total_area)::numeric, 2) AS "Средняя площадь",
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY rooms) AS "Медиана кол-ва комнат",
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY balcony) AS "Медиана кол-ва балконов",
    PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY floors_total) AS "Медиана этажности",
    ROUND(AVG(ceiling_height)::numeric, 2) AS "Средняя высота потолка"
FROM categorized
WHERE exposition_category IS NOT NULL
GROUP BY city_category, exposition_category
ORDER BY city_category, exposition_category;


-- Задача 2. Анализ сезонности объявлений
-- Анализируем количество публикаций и снятий объявлений по месяцам.
-- Сравниваем сезонную динамику этих показателей, а также
-- среднюю стоимость квадратного метра и среднюю площадь объектов.
-- Это позволяет выявить месяцы с наибольшей и наименьшей активностью
-- и оценить изменение характеристик выставленной на продажу недвижимости.

-- Определим аномальные значения (выбросы) по значению перцентилей:
WITH limits AS (
    SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats     
),
-- Найдём id объявлений, которые не содержат выбросы:
filtered_id AS (
    SELECT id
    FROM real_estate.flats  
    WHERE 
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
            AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
),
-- Базовая таблица (без фильтрации days_exposition):
base AS (
    SELECT
        f.id,
        f.total_area,
        ROUND((a.last_price / f.total_area)::numeric, 2) AS price_per_sqm,
        a.first_day_exposition,
        a.days_exposition,
        (a.first_day_exposition + (a.days_exposition || ' days')::interval)::date AS remove_date
    FROM real_estate.flats AS f
    JOIN real_estate.advertisement AS a ON f.id = a.id
    JOIN real_estate.type AS t ON f.type_id = t.type_id
    WHERE f.total_area IS NOT NULL
      AND a.last_price IS NOT NULL
      AND a.first_day_exposition IS NOT NULL
      AND t.type = 'город'
      AND f.id IN (SELECT id FROM filtered_id)
),
-- Месяцы:
by_month AS (
    SELECT
        id,
        total_area,
        price_per_sqm,
        EXTRACT(MONTH FROM first_day_exposition)::int AS month_pub,
        EXTRACT(MONTH FROM remove_date)::int AS month_remove,
        days_exposition
    FROM base
),
-- Статистика по публикациям:
pub_stats AS (
    SELECT
        month_pub AS month,
        COUNT(*) AS pub_count,
        ROUND(AVG(price_per_sqm)::numeric, 2) AS avg_price_sqm_pub,
        ROUND(AVG(total_area)::numeric, 2) AS avg_area_pub,
        RANK() OVER (ORDER BY COUNT(*) DESC) AS pub_rank
    FROM by_month
    GROUP BY month_pub
),
-- Статистика по снятиям (только где days_exposition IS NOT NULL):
remove_stats AS (
    SELECT
        month_remove AS month,
        COUNT(*) AS remove_count,
        ROUND(AVG(price_per_sqm)::numeric, 2) AS avg_price_sqm_remove,
        ROUND(AVG(total_area)::numeric, 2) AS avg_area_remove,
        RANK() OVER (ORDER BY COUNT(*) DESC) AS remove_rank
    FROM by_month
    WHERE days_exposition IS NOT NULL
    GROUP BY month_remove
)
-- Итог:
SELECT
    COALESCE(p.month, r.month) AS "Месяц",
    COALESCE(pub_count, 0) AS "Количество публикаций",
    COALESCE(remove_count, 0) AS "Количество снятий",
    p.avg_price_sqm_pub AS "Средняя цена за кв.м (публикации)",
    p.avg_area_pub AS "Средняя площадь (публикации)",
    r.avg_price_sqm_remove AS "Средняя цена за кв.м (снятия)",
    r.avg_area_remove AS "Средняя площадь (снятия)",
    p.pub_rank AS "Ранг по публикациям",
    r.remove_rank AS "Ранг по снятиям"
FROM pub_stats p
FULL OUTER JOIN remove_stats r
    ON p.month = r.month
ORDER BY "Месяц";


-- Задача 3. Анализ рынка недвижимости Ленинградской области
-- Сравниваем населённые пункты по количеству опубликованных объявлений
-- и доле объявлений, снятых с публикации.
-- Анализируем среднюю стоимость квадратного метра, среднюю площадь объектов
-- и продолжительность экспозиции.
-- Это позволяет выявить различия между населёнными пунктами
-- по активности рынка, характеристикам недвижимости и срокам экспозиции.

-- Определим аномальные значения (выбросы) по значению перцентилей:
WITH limits AS (
    SELECT  
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY total_area) AS total_area_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY rooms) AS rooms_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY balcony) AS balcony_limit,
        PERCENTILE_DISC(0.99) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_h,
        PERCENTILE_DISC(0.01) WITHIN GROUP (ORDER BY ceiling_height) AS ceiling_height_limit_l
    FROM real_estate.flats     
),
 -- Найдём id объявлений, которые не содержат выбросы:
filtered_id AS (
    SELECT id
    FROM real_estate.flats  
    WHERE 
        total_area < (SELECT total_area_limit FROM limits)
        AND (rooms < (SELECT rooms_limit FROM limits) OR rooms IS NULL)
        AND (balcony < (SELECT balcony_limit FROM limits) OR balcony IS NULL)
        AND ((ceiling_height < (SELECT ceiling_height_limit_h FROM limits)
            AND ceiling_height > (SELECT ceiling_height_limit_l FROM limits)) OR ceiling_height IS NULL)
),
-- Считаем агрегаты по каждому населённому пункту
agg AS (
    SELECT 
        c.city AS "Населённый пункт",
        COUNT(*) FILTER (WHERE a.first_day_exposition IS NOT NULL) AS "Количество публикаций",
        COUNT(*) FILTER (WHERE a.days_exposition IS NOT NULL) AS "Количество снятий",
        ROUND(AVG(a.last_price / f.total_area)) AS "Средняя цена за кв.м",
        ROUND(AVG(f.total_area)::numeric, 2) AS "Средняя площадь",
        ROUND(PERCENTILE_CONT(0.5) WITHIN GROUP (ORDER BY a.days_exposition)) AS "Медиана экспозиции",
        ROUND(AVG(a.days_exposition)) AS "Средняя экспозиция",
        ROUND(100.0 * COUNT(*) FILTER (WHERE a.days_exposition IS NOT NULL) / COUNT(*), 2) 
            AS "Доля снятых (%)"
    FROM real_estate.advertisement a
    JOIN real_estate.flats f ON a.id = f.id
    JOIN real_estate.city c ON f.city_id = c.city_id
    WHERE f.id IN (SELECT id FROM filtered_id)  -- только без выбросов
      AND c.city NOT ILIKE '%Санкт-Петербург%'  -- исключаем Санкт-Петербург
    GROUP BY c.city
),
-- Добавляем ранжирование по ключевым показателям
ranked AS (
    SELECT 
        *,
        RANK() OVER (ORDER BY "Количество публикаций" DESC) AS "Ранг по публикациям",
        RANK() OVER (ORDER BY "Доля снятых (%)" DESC) AS "Ранг по доле снятых",
        RANK() OVER (ORDER BY "Медиана экспозиции") AS "Ранг по скорости продажи"
    FROM agg
)
-- Выводим итоговую таблицу, сортируя по числу публикаций и оставляем топ-30
SELECT *
FROM ranked
ORDER BY "Количество публикаций" DESC
LIMIT 30;