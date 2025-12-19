# Задание 1. B-tree индексы в PostgreSQL

1. Запустите БД через docker compose в ./src/docker-compose.yml:

2. Выполните запрос для поиска книги с названием 'Oracle Core' и получите план выполнения:
   ```sql
   EXPLAIN ANALYZE
   SELECT * FROM t_books WHERE title = 'Oracle Core';
   ```
   
   *План выполнения:*
    Seq Scan on t_books  (cost=0.00..3100.00 rows=1 width=33) (actual time=14.691..14.692 rows=1 loops=1)
  Filter: ((title)::text = 'Oracle Core'::text)
  Rows Removed by Filter: 149999
Planning Time: 0.544 ms
Execution Time: 14.779 ms


   
   *Объясните результат:*
* `Seq Scan` — PostgreSQL прочитал **всю таблицу**, потому что **индекса по `title` ещё нет**. 
* `Rows Removed by Filter: 149999` — столько строк было **проверено и отброшено** условием `title = 'Oracle Core'`.
* `Planning Time` — время построения плана, `Execution Time` — время выполнения запроса на сервере (строка `Time:` из `\timing` может быть больше, т.к. это замер на клиенте + вывод результата). 



3. Создайте B-tree индексы:
   ```sql
   CREATE INDEX t_books_title_idx ON t_books(title);
   CREATE INDEX t_books_active_idx ON t_books(is_active);
   ```
   
   *Результат:*
```
CREATE INDEX
CREATE INDEX
```

4. Проверьте информацию о созданных индексах:
   ```sql
   SELECT schemaname, tablename, indexname, indexdef
   FROM pg_catalog.pg_indexes
   WHERE tablename = 't_books';
   ```
   
   *Результат:*
```text
 schemaname | tablename |     indexname      |                                 indexdef
------------+-----------+--------------------+---------------------------------------------------------------------------
 public     | t_books   | t_books_id_pk      | CREATE UNIQUE INDEX t_books_id_pk ON public.t_books USING btree (book_id)
 public     | t_books   | t_books_title_idx  | CREATE INDEX t_books_title_idx ON public.t_books USING btree (title)
 public     | t_books   | t_books_active_idx | CREATE INDEX t_books_active_idx ON public.t_books USING btree (is_active)
(3 rows)

```   
   *Объясните результат:*
```
pg_indexes — системное представление со списком индексов: схема/таблица/имя/DDL (indexdef).

t_books_id_pk — уникальный B-tree индекс, созданный автоматически для PRIMARY KEY по book_id (нужен, чтобы обеспечивать уникальность ключа).
+1

t_books_title_idx и t_books_active_idx — твои индексы на title и is_active; метод btree указан в indexdef (по умолчанию CREATE INDEX создаёт B-tree).
```

5. Обновите статистику таблицы:
   ```sql
   ANALYZE t_books;
   ```
   
   *Результат:*

```
ANALYZE
```

6. Выполните запрос для поиска книги 'Oracle Core' и получите план выполнения:
   ```sql
   EXPLAIN ANALYZE
   SELECT * FROM t_books WHERE title = 'Oracle Core';
   ```
   
   *План выполнения:*
   [Вставьте план выполнения]
   
   *Объясните результат:*
   [Ваше объяснение]

7. Выполните запрос для поиска книги по book_id и получите план выполнения:
   ```sql
   EXPLAIN ANALYZE
   SELECT * FROM t_books WHERE book_id = 18;
   ```
   
   *План выполнения:*
```text
Index Scan using t_books_title_idx on t_books  (cost=0.42..8.44 rows=1 width=33) (actual time=0.075..0.076 rows=1 loops=1)
  Index Cond: ((title)::text = 'Oracle Core'::text)
Planning Time: 0.582 ms
Execution Time: 0.280 ms
```   
   *Объясните результат:*
Объяснение:

Теперь используется Index Scan по индексу t_books_title_idx: Postgres находит нужное значение в индексе и читает только подходящую строку из таблицы.

Index Cond — условие, которое применяется на уровне индекса (по нему выбираются записи в индексе), поэтому не нужно просматривать всю таблицу.

Время выполнения стало сильно меньше, чем при Seq Scan (у тебя было ~14.8 ms, стало ~0.28 ms), потому что читается не 150k строк, а фактически 1 строка.

8. Выполните запрос для поиска активных книг и получите план выполнения:
   ```sql
   EXPLAIN ANALYZE
   SELECT * FROM t_books WHERE is_active = true;
   ```
   
   *План выполнения:*
```text
Index Scan using t_books_id_pk on t_books  (cost=0.42..8.44 rows=1 width=33) (actual time=0.074..0.075 rows=1 loops=1)
  Index Cond: (book_id = 18)
Planning Time: 0.229 ms
Execution Time: 0.096 ms
```
   
   *Объясните результат:*

Используется Index Scan по индексу t_books_id_pk, потому что book_id — PRIMARY KEY, а для PK Postgres автоматически создаёт уникальный B-tree индекс. 

Index Cond: (book_id = 18) — условие отрабатывает на уровне индекса, поэтому находится ровно 1 строка без полного сканирования таблицы. 


9. Посчитайте количество строк и уникальных значений:
   ```sql
   SELECT 
       COUNT(*) as total_rows,
       COUNT(DISTINCT title) as unique_titles,
       COUNT(DISTINCT category) as unique_categories,
       COUNT(DISTINCT author) as unique_authors
   FROM t_books;
   ```
   
   *Результат:*
```
 total_rows | unique_titles | unique_categories | unique_authors 
------------+---------------+-------------------+----------------
     150000 |        150000 |                 6 |           1003
(1 row)

```

10. Удалите созданные индексы:
    ```sql
    DROP INDEX t_books_title_idx;
    DROP INDEX t_books_active_idx;
    ```
    
    *Результат:*
```text
DROP INDEX
DROP INDEX
```

11. Основываясь на предыдущих результатах, создайте индексы для оптимизации следующих запросов:
    a. `WHERE title = $1 AND category = $2`
    b. `WHERE title = $1`
    c. `WHERE category = $1 AND author = $2`
    d. `WHERE author = $1 AND book_id = $2`
    
    *Созданные индексы:*
```sql
-- (a) title = $1 AND category = $2  (+ одновременно покрывает (b) title = $1)
CREATE INDEX t_books_title_category_idx ON t_books(title, category);

-- (c) category = $1 AND author = $2
CREATE INDEX t_books_author_category_idx ON t_books(author, category);

-- (d) отдельный индекс НЕ создаю: достаточно PK-индекса t_books_id_pk по book_id
-- (PostgreSQL сам создаёт уникальный B-tree индекс для PRIMARY KEY)
```

    *Объясните ваше решение:*
```text
Для (a) делаем составной B-tree (title, category): запрос фильтрует по обоим полям, и индекс может сразу сузить поиск. Такой индекс также подходит для (b) WHERE title = $1, потому что используется левый префикс индекса (условие по первой колонке). 
Для (c) делаем (author, category): в WHERE обе проверки на равенство, порядок в запросе не важен, но первой выгодно ставить более селективную колонку (author у нас сильно разнообразнее, чем category), и этот индекс потенциально полезен и для запросов только по author. 
Для (d) отдельный индекс не нужен, потому что book_id — PRIMARY KEY и по нему уже есть автоматический уникальный B-tree индекс (t_books_id_pk), который точечно находит строку; проверка author = $1 дальше выполняется как дополнительный фильтр по найденной записи.
```

12. Протестируйте созданные индексы.
````md
### 12) Тестирование созданных индексов

> Перед тестами лучше обновлять статистику:
```sql
ANALYZE t_books;
````

`EXPLAIN ANALYZE` показывает реальный план и фактическое время выполнения.

---

#### (a) `WHERE title = $1 AND category = $2`

**Запрос:**

```sql
EXPLAIN ANALYZE
SELECT * FROM t_books
WHERE title = 'Oracle Core' AND category = 'Databases';
```

**План выполнения:**

```text
Index Scan using t_books_title_idx on t_books  (cost=0.42..8.44 rows=1 width=33) (actual time=0.133..0.134 rows=1 loops=1)
  Index Cond: ((title)::text = 'Oracle Core'::text)
  Filter: ((category)::text = 'Databases'::text)
Planning Time: 0.505 ms
Execution Time: 0.279 ms
```

**Объяснение:**

* Используется индекс **только по `title`** (`Index Cond`), а `category` проверяется уже после нахождения строки как `Filter`, т.к. в этом индексе нет `category`. 
* Если создать составной индекс `(title, category)`, оба условия могли бы оказаться в `Index Cond`. 

---

#### (b) `WHERE title = $1`

**Запрос:**

```sql
EXPLAIN ANALYZE
SELECT * FROM t_books
WHERE title = 'Oracle Core';
```

**План выполнения:**

```text
Index Scan using t_books_title_idx on t_books  (cost=0.42..8.44 rows=1 width=33) (actual time=0.045..0.047 rows=1 loops=1)
  Index Cond: ((title)::text = 'Oracle Core'::text)
Planning Time: 0.115 ms
Execution Time: 0.077 ms
```

**Объяснение:**

* Полный матч по `title` → планировщик использует `Index Scan` по `t_books_title_idx`, условие попадает в `Index Cond`. ([Crunchy Data][3])

---

#### (c) `WHERE category = $1 AND author = $2`

**Запрос:**

```sql
EXPLAIN ANALYZE
SELECT * FROM t_books
WHERE category = 'Databases' AND author = 'Tom Lane';
```

**План выполнения:**

```text
Seq Scan on t_books  (cost=0.00..3475.00 rows=1 width=33) (actual time=15.249..15.250 rows=1 loops=1)
  Filter: (((category)::text = 'Databases'::text) AND ((author)::text = 'Tom Lane'::text))
  Rows Removed by Filter: 149999
Planning Time: 0.116 ms
Execution Time: 15.265 ms
```

**Объяснение:**

* `Seq Scan` значит, что **подходящего индекса под (author, category) у тебя сейчас нет**, поэтому Postgres читает всю таблицу и отбрасывает 149999 строк фильтром. 
* Чтобы оптимизировать этот запрос, нужен составной индекс (например) `(author, category)` (мультиколоночные B-tree эффективнее всего при ограничениях на ведущие колонки). 

---

#### (d) `WHERE author = $1 AND book_id = $2`

**Запрос:**

```sql
EXPLAIN ANALYZE
SELECT * FROM t_books
WHERE author = 'Tom Lane' AND book_id = 2025;
```

**План выполнения:**

```text
Index Scan using t_books_id_pk on t_books  (cost=0.42..8.44 rows=1 width=33) (actual time=0.075..0.077 rows=1 loops=1)
  Index Cond: (book_id = 2025)
  Filter: ((author)::text = 'Tom Lane'::text)
Planning Time: 0.085 ms
Execution Time: 0.104 ms
```

**Объяснение:**

* Используется индекс первичного ключа `t_books_id_pk`: по `book_id` находится 1 строка (`Index Cond`), а `author` проверяется дополнительно как `Filter`.
* Отдельный индекс под `(author, book_id)` обычно не обязателен, т.к. `book_id` уникален и уже даёт точечный поиск.


13. Выполните регистронезависимый поиск по началу названия:
    ```sql
    EXPLAIN ANALYZE
    SELECT * FROM t_books WHERE title ILIKE 'Relational%';
    ```
    
    *План выполнения:*
```text
text
Seq Scan on t_books  (cost=0.00..3100.00 rows=15 width=33) (actual time=53.048..53.049 rows=0 loops=1)
  Filter: ((title)::text ~~* 'Relational%'::text)
  Rows Removed by Filter: 150000
Planning Time: 1.457 ms
Execution Time: 53.083 ms
```
    
    *Объясните результат:*
Seq Scan — таблица читается целиком: для ILIKE (оператор ~~*) обычный B-tree индекс по title обычно не используется, поэтому Postgres проверяет условие для каждой строки. 

rows=0 и Rows Removed by Filter: 150000 — ни одна строка не подошла под шаблон Relational%, поэтому все 150000 строк были просмотрены и отброшены фильтром


14. Создайте функциональный индекс:
    ```sql
    CREATE INDEX t_books_up_title_idx ON t_books(UPPER(title));
    ```
    
    *Результат:*
```text
CREATE INDEX
```

15. Выполните запрос из шага 13 с использованием UPPER:
    ```sql
    EXPLAIN ANALYZE
    SELECT * FROM t_books WHERE UPPER(title) LIKE 'RELATIONAL%';
    ```
    
    *План выполнения:*
```text
Seq Scan on t_books  (cost=0.00..3475.00 rows=750 width=33) (actual time=33.177..33.178 rows=0 loops=1)
  Filter: (upper((title)::text) ~~ 'RELATIONAL%'::text)
  Rows Removed by Filter: 150000
Planning Time: 0.470 ms
Execution Time: 33.216 ms
```
    
    *Объясните результат:*
Несмотря на функциональный индекс t_books_up_title_idx, планировщик выбрал Seq Scan: в текущей конфигурации обычный B-tree индекс по тексту/выражению может не применяться для LIKE 'PREFIX%' (часто из-за правил сравнения строк/колляции). Для таких префиксных LIKE обычно делают индекс с операторным классом text_pattern_ops (в т.ч. на UPPER(title)).

rows=0 и Rows Removed by Filter: 150000 — подходящих строк нет, поэтому были проверены и отброшены все строки таблицы.


16. Выполните поиск подстроки:
    ```sql
    EXPLAIN ANALYZE
    SELECT * FROM t_books WHERE title ILIKE '%Core%';
    ```
    
    *План выполнения:*
```text
Seq Scan on t_books  (cost=0.00..3100.00 rows=15 width=33) (actual time=48.038..48.040 rows=1 loops=1)
  Filter: ((title)::text ~~* '%Core%'::text)
  Rows Removed by Filter: 149999
Planning Time: 0.222 ms
Execution Time: 48.090 ms
```
    
    *Объясните результат:*
Seq Scan потому что шаблон начинается с % → B-tree индекс не помогает (нельзя “зацепиться” за начало строки), поэтому Postgres проверяет условие для каждой строки.

Нашлась 1 строка, остальные 149999 были отброшены фильтром (Rows Removed by Filter).

Для ускорения таких запросов обычно используют pg_trgm + GIN/GiST индекс (он умеет ускорять LIKE/ILIKE с %...%).

17. Попробуйте удалить все индексы:
    ```sql
    DO $$ 
    DECLARE
        r RECORD;
    BEGIN
        FOR r IN (SELECT indexname FROM pg_indexes 
                  WHERE tablename = 't_books' 
                  AND indexname != 'books_pkey')
        LOOP
            EXECUTE 'DROP INDEX ' || r.indexname;
        END LOOP;
    END $$;
    ```
    
    *Результат:*
```text
```text
ERROR:  cannot drop index t_books_id_pk because constraint t_books_id_pk on table t_books requires it
HINT:  You can drop constraint t_books_id_pk on table t_books instead.
CONTEXT:  SQL statement "DROP INDEX t_books_id_pk"
PL/pgSQL function inline_code_block line 9 at EXECUTE
```
    
    *Объясните результат:*
Индекс t_books_id_pk обслуживает ограничение PRIMARY KEY, поэтому его нельзя удалить обычным DROP INDEX (PostgreSQL защищает constraint).

В твоём DO-блоке исключается books_pkey, но у тебя PK-индекс называется t_books_id_pk, поэтому цикл пытается снести именно его и падает.

Если нужно удалить “всё кроме PK”, надо исключать t_books_id_pk (или удалять constraint через ALTER TABLE ... DROP CONSTRAINT, но это уже удалит PK).

18. Создайте индекс для оптимизации суффиксного поиска:
    ```sql
    -- Вариант 1: с reverse()
    CREATE INDEX t_books_rev_title_idx ON t_books(reverse(title));
    
    -- Вариант 2: с триграммами
    CREATE EXTENSION IF NOT EXISTS pg_trgm;
    CREATE INDEX t_books_trgm_idx ON t_books USING gin (title gin_trgm_ops);
    ```
    
    *Результаты тестов:*
```text
CREATE INDEX
CREATE EXTENSION
CREATE INDEX

```
    
    *Объясните результаты:*
    [Ваше объяснение]

19. Выполните поиск по точному совпадению:
    ```sql
    EXPLAIN ANALYZE
    SELECT * FROM t_books WHERE title = 'Oracle Core';
    ```
    
    *План выполнения:*
```text
Index Scan using t_books_title_idx on t_books  (cost=0.42..8.44 rows=1 width=33) (actual time=0.104..0.105 rows=1 loops=1)
  Index Cond: ((title)::text = 'Oracle Core'::text)
Planning Time: 1.120 ms
Execution Time: 0.132 ms
```
    
    *Объясните результат:*
Index Scan using t_books_title_idx — PostgreSQL использует B-tree индекс по title, чтобы быстро найти нужную строку без чтения всей таблицы.

Index Cond — условие применяется на уровне индекса (по нему выбираются подходящие записи), поэтому запрос работает быстро

Planning Time — время построения плана, Execution Time — фактическое время выполнения запроса на сервере при EXPLAIN ANALYZE.


20. Выполните поиск по началу названия:
    ```sql
    EXPLAIN ANALYZE
    SELECT * FROM t_books WHERE title ILIKE 'Relational%';
    ```
    
    *План выполнения:*
```text
Bitmap Heap Scan on t_books  (cost=95.15..150.36 rows=15 width=33) (actual time=0.243..0.244 rows=0 loops=1)
  Recheck Cond: ((title)::text ~~* 'Relational%'::text)
  Rows Removed by Index Recheck: 1
  Heap Blocks: exact=1
  ->  Bitmap Index Scan on t_books_trgm_idx  (cost=0.00..95.15 rows=15 width=0) (actual time=0.230..0.230 rows=1 loops=1)
        Index Cond: ((title)::text ~~* 'Relational%'::text)
Planning Time: 0.357 ms
Execution Time: 0.398 ms
```
    
    *Объясните результат:*
Используется триграммный GIN-индекс t_books_trgm_idx: сначала Bitmap Index Scan строит “карту” подходящих мест, затем Bitmap Heap Scan читает нужные страницы таблицы.

Recheck Cond и Rows Removed by Index Recheck: 1 означают, что индекс нашёл 1 кандидата, но при перепроверке по исходному условию строка не подошла (у GIN/pg_trgm возможны ложные срабатывания, поэтому нужна перепроверка).

Heap Blocks: exact=1 — реально прочитана всего 1 страница таблицы, поэтому запрос получился очень быстрым (~0.4 ms).

21. Создайте свой пример индекса с обратной сортировкой:
    ```sql
    CREATE INDEX t_books_desc_idx ON t_books(title DESC);
    ```
    
    *Тестовый запрос:*
```text
EXPLAIN ANALYZE
SELECT title
FROM t_books
ORDER BY title DESC
LIMIT 10;

```
    
    *План выполнения:*
```text
 Limit  (cost=0.42..0.73 rows=10 width=11) (actual time=0.068..0.070 rows=10 loops=1)
   ->  Index Only Scan using t_books_desc_idx on t_books  (cost=0.42..4585.51 rows=150000 width=11) (actual time=0.067..0.068 rows=10 loops=1)
         Heap Fetches: 0
 Planning Time: 0.599 ms
 Execution Time: 0.128 ms
(5 rows)

```
    
    *Объясните результат:*
Index Only Scan using t_books_desc_idx — запрос берёт только title, и этот столбец есть в индексе, поэтому PostgreSQL смог читать данные прямо из индекса, не обращаясь к таблице.

Heap Fetches: 0 — не понадобилось ни одного чтения из “кучи” (таблицы), т.к. по visibility map сервер понял, что строки видимы и можно обойтись индексом.

ORDER BY title DESC + LIMIT 10 — индекс уже хранит значения в нужном порядке, поэтому отдельной сортировки нет: узел Limit просто берёт первые 10 записей из индексного скана.