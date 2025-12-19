# Задание 2: Специальные случаи использования индексов

# Партиционирование и специальные случаи использования индексов

1. Удалите прошлый инстанс PostgreSQL - `docker-compose down` в папке `src` и запустите новый: `docker-compose up -d`.

2. Создайте партиционированную таблицу и заполните её данными:

    ```sql
    -- Создание партиционированной таблицы
    CREATE TABLE t_books_part (
        book_id     INTEGER      NOT NULL,
        title       VARCHAR(100) NOT NULL,
        category    VARCHAR(30),
        author      VARCHAR(100) NOT NULL,
        is_active   BOOLEAN      NOT NULL
    ) PARTITION BY RANGE (book_id);

    -- Создание партиций
    CREATE TABLE t_books_part_1 PARTITION OF t_books_part
        FOR VALUES FROM (MINVALUE) TO (50000);

    CREATE TABLE t_books_part_2 PARTITION OF t_books_part
        FOR VALUES FROM (50000) TO (100000);

    CREATE TABLE t_books_part_3 PARTITION OF t_books_part
        FOR VALUES FROM (100000) TO (MAXVALUE);

    -- Копирование данных из t_books
    INSERT INTO t_books_part 
    SELECT * FROM t_books;
    ```

3. Обновите статистику таблиц:
   ```sql
   ANALYZE t_books;
   ANALYZE t_books_part;
   ```
   
   *Результат:*
```text
ANALYZE
ANALYZE
```

4. Выполните запрос для поиска книги с id = 18:
   ```sql
   EXPLAIN ANALYZE
   SELECT * FROM t_books_part WHERE book_id = 18;
   ```
   
   *План выполнения:*
```text
Seq Scan on t_books_part_1 t_books_part  (cost=0.00..1032.99 rows=1 width=32) (actual time=0.011..2.788 rows=1 loops=1)
   Filter: (book_id = 18)
   Rows Removed by Filter: 49998
 Planning Time: 12.759 ms
 Execution Time: 2.833 ms
(5 rows)

```
   
   *Объясните результат:*
- `Seq Scan on t_books_part_1` — PostgreSQL читает **только партицию `t_books_part_1`**, потому что условие `book_id = 18` задано по **ключу партиционирования** (`book_id`) и сработало *partition pruning* (ненужные партиции исключены из плана). 
- Почему всё равно `Seq Scan`, а не индекс: в `t_books_part` ты **не создавал PRIMARY KEY/индекс на `book_id`**, поэтому искать “точечно” нечем → остаётся последовательное сканирование выбранной партиции. (Pruning работает по границам партиций и не требует индексов.)  
- `Rows Removed by Filter: 49998` — столько строк в этой партиции было просмотрено и отброшено фильтром, пока не нашли нужную (`book_id=18`). Это стандартная метрика `EXPLAIN ANALYZE` для фильтрации.

5. Выполните поиск по названию книги:
   ```sql
   EXPLAIN ANALYZE
   SELECT * FROM t_books_part 
   WHERE title = 'Expert PostgreSQL Architecture';
   ```
   
   *План выполнения:*
```text
Append  (cost=0.00..3100.01 rows=3 width=33) (actual time=4.274..9.962 rows=1 loops=1)
  ->  Seq Scan on t_books_part_1  (cost=0.00..1032.99 rows=1 width=32) (actual time=4.273..4.273 rows=1 loops=1)
        Filter: ((title)::text = 'Expert PostgreSQL Architecture'::text)
        Rows Removed by Filter: 49998
  ->  Seq Scan on t_books_part_2  (cost=0.00..1034.00 rows=1 width=33) (actual time=2.906..2.906 rows=0 loops=1)
        Filter: ((title)::text = 'Expert PostgreSQL Architecture'::text)
        Rows Removed by Filter: 50000
  ->  Seq Scan on t_books_part_3  (cost=0.00..1033.01 rows=1 width=34) (actual time=2.776..2.776 rows=0 loops=1)
        Filter: ((title)::text = 'Expert PostgreSQL Architecture'::text)
        Rows Removed by Filter: 50001
Planning Time: 0.993 ms
Execution Time: 10.036 ms
```
   
   *Объясните результат:*

Append = запрос выполнен как объединение результатов из всех партиций (т.е. план включает сканы t_books_part_1, _2, _3).

Условие WHERE title = ... не по ключу партиционирования (book_id), поэтому partition pruning не сработал — планировщик не может исключить партиции по диапазонам book_id, и приходится проверять каждую.

Внутри каждой партиции Seq Scan, потому что индекса по title ещё нет → строки читаются подряд, а неподходящие считаются в Rows Removed by Filter.

6. Создайте партиционированный индекс:
   ```sql
   CREATE INDEX ON t_books_part(title);
   ```
   
   *Результат:*
```text
CREATE INDEX
```

7. Повторите запрос из шага 5:
   ```sql
   EXPLAIN ANALYZE
   SELECT * FROM t_books_part 
   WHERE title = 'Expert PostgreSQL Architecture';
   ```
   
   *План выполнения:*
```
Append  (cost=0.29..24.94 rows=3 width=33) (actual time=0.038..0.105 rows=1 loops=1)
  ->  Index Scan using t_books_part_1_title_idx on t_books_part_1  (cost=0.29..8.31 rows=1 width=32) (actual time=0.037..0.038 rows=1 loops=1)
        Index Cond: ((title)::text = 'Expert PostgreSQL Architecture'::text)
  ->  Index Scan using t_books_part_2_title_idx on t_books_part_2  (cost=0.29..8.31 rows=1 width=33) (actual time=0.037..0.037 rows=0 loops=1)
        Index Cond: ((title)::text = 'Expert PostgreSQL Architecture'::text)
  ->  Index Scan using t_books_part_3_title_idx on t_books_part_3  (cost=0.29..8.31 rows=1 width=34) (actual time=0.028..0.028 rows=0 loops=1)
        Index Cond: ((title)::text = 'Expert PostgreSQL Architecture'::text)
Planning Time: 0.880 ms
Execution Time: 0.148 ms
```
   
   *Объясните результат:*

CREATE INDEX ON t_books_part(title) создал “родительский” индекс и автоматически создал/прикрепил соответствующие индексы на всех партициях (t_books_part_1_title_idx, _2_..., _3_...). 

В плане всё ещё Append, потому что фильтр идёт по title, а ключ партиционирования — book_id, поэтому partition pruning тут не помогает и планировщик проверяет все партиции (но уже через индекс). 

Внутри каждой партиции теперь Index Scan с Index Cond, поэтому выполнение стало гораздо быстрее, чем в шаге 5 с Seq Scan. 

8. Удалите созданный индекс:
   ```sql
   DROP INDEX t_books_part_title_idx;
   ```
   
   *Результат:*
DROP INDEX

При удалении индекса на партиционированной таблице PostgreSQL удаляет и индексы-«части» на партициях (потому что они являются партициями этого индекса)

9. Создайте индекс для каждой партиции:
   ```sql
   CREATE INDEX ON t_books_part_1(title);
   CREATE INDEX ON t_books_part_2(title);
   CREATE INDEX ON t_books_part_3(title);
   ```
   
   *Результат:*
```text
CREATE INDEX
CREATE INDEX
CREATE INDEX
```

10. Повторите запрос из шага 5:
    ```sql
    EXPLAIN ANALYZE
    SELECT * FROM t_books_part 
    WHERE title = 'Expert PostgreSQL Architecture';
    ```
    
    *План выполнения:*
```text
 Append  (cost=0.29..24.94 rows=3 width=33) (actual time=0.037..0.091 rows=1 loops=1)
   ->  Index Scan using t_books_part_1_title_idx1 on t_books_part_1  (cost=0.29..8.31 rows=1 width=32) (actual time=0.036..0.037 rows=1 loops=1)
         Index Cond: ((title)::text = 'Expert PostgreSQL Architecture'::text)
   ->  Index Scan using t_books_part_2_title_idx1 on t_books_part_2  (cost=0.29..8.31 rows=1 width=33) (actual time=0.028..0.028 rows=0 loops=1)
         Index Cond: ((title)::text = 'Expert PostgreSQL Architecture'::text)
   ->  Index Scan using t_books_part_3_title_idx1 on t_books_part_3  (cost=0.29..8.31 rows=1 width=34) (actual time=0.024..0.024 rows=0 loops=1)
         Index Cond: ((title)::text = 'Expert PostgreSQL Architecture'::text)
 Planning Time: 1.053 ms
 Execution Time: 0.129 ms
(9 rows) 
```
    
    *Объясните результат:*
Append означает, что PostgreSQL собирает результат из нескольких партиций: условие фильтрации по title не связано с ключом партиционирования (book_id), поэтому partition pruning тут не исключает партиции, и план проверяет все. 

Внутри каждой партиции теперь Index Scan с Index Cond — т.е. поиск делается через индекс по title, а не через полный Seq Scan, поэтому время стало маленьким (~0.13 ms). 

Суффикс в именах ..._idx1 появился потому, что имена индексов в схеме должны быть уникальны: когда “идеальное” имя уже занято, PostgreSQL/клиент генерирует следующее свободное имя (часто добавляя цифру).
11. Удалите созданные индексы:
    ```sql
    DROP INDEX t_books_part_1_title_idx;
    DROP INDEX t_books_part_2_title_idx;
    DROP INDEX t_books_part_3_title_idx;
    ```
    
    *Результат:*


12. Создайте обычный индекс по book_id:
    ```sql
    CREATE INDEX t_books_part_idx ON t_books_part(book_id);
    ```
    
    *Результат:*
CREATE INDEX


13. Выполните поиск по book_id:
    ```sql
    EXPLAIN ANALYZE
    SELECT * FROM t_books_part WHERE book_id = 11011;
    ```
    
    *План выполнения:*
 Index Scan using t_books_part_1_book_id_idx on t_books_part_1 t_books_part  (cost=0.29..8.31 rows=1 width=32) (actual time=0.029..0.030 rows=1 loops=1)
   Index Cond: (book_id = 11011)
 Planning Time: 0.562 ms
 Execution Time: 0.049 ms
(4 rows)

    
    *Объясните результат:*
Индексы t_books_part_1_title_idx, t_books_part_2_title_idx, t_books_part_3_title_idx являются частями (partition indexes), прикреплёнными к родительскому индексу t_books_part_title_idx.

Прикреплённый (attached) индекс нельзя удалить отдельно — его нужно удалять через удаление родительского индекса (DROP INDEX t_books_part_title_idx), тогда все дочерние индексы удалятся автоматически


14. Создайте индекс по полю is_active:
    ```sql
    CREATE INDEX t_books_active_idx ON t_books(is_active);
    ```
    
    *Результат:*
    CREATE INDEX

15. Выполните поиск активных книг с отключенным последовательным сканированием:
    ```sql
    SET enable_seqscan = off;
    EXPLAIN ANALYZE
    SELECT * FROM t_books WHERE is_active = true;
    SET enable_seqscan = on;
    ```
    
    *План выполнения:*
 Bitmap Heap Scan on t_books  (cost=1010.53..3136.48 rows=90095 width=33) (actual time=2.170..9.631 rows=89806 loops=1)
   Recheck Cond: is_active
   Heap Blocks: exact=1225
   ->  Bitmap Index Scan on t_books_active_idx  (cost=0.00..988.01 rows=90095 width=0) (actual time=2.028..2.028 rows=89806 loops=1)
         Index Cond: (is_active = true)
 Planning Time: 0.080 ms
 Execution Time: 12.467 ms
(7 rows)

    
    *Объясните результат:*

Ты принудительно “отговорил” планировщик от Seq Scan через SET enable_seqscan = off, поэтому он выбрал план с индексом (это настройка для экспериментов; полностью запретить seq scan всё равно нельзя). 

Bitmap Index Scan строит bitmap подходящих строк по индексу t_books_active_idx, а Bitmap Heap Scan затем читает нужные страницы таблицы пачками — так выгоднее, когда совпадений много (у тебя ~89806 строк). 

Recheck Cond означает перепроверку условия на строках при чтении из таблицы (часто важно, когда bitmap может быть “lossy”); у тебя Heap Blocks: exact=1225, т.е. bitmap был точным.

16. Создайте составной индекс:
    ```sql
    CREATE INDEX t_books_author_title_index ON t_books(author, title);
    ```
    
    *Результат:*
CREATE INDEX


17. Найдите максимальное название для каждого автора:
    ```sql
    EXPLAIN ANALYZE
    SELECT author, MAX(title) 
    FROM t_books 
    GROUP BY author;
    ```
    
    *План выполнения:*
 HashAggregate  (cost=3475.00..3485.00 rows=1000 width=42) (actual time=38.201..38.308 rows=1003 loops=1)
   Group Key: author
   Batches: 1  Memory Usage: 193kB
   ->  Seq Scan on t_books  (cost=0.00..2725.00 rows=150000 width=21) (actual time=0.008..6.505 rows=150000 loops=1)
 Planning Time: 0.828 ms
 Execution Time: 38.959 ms
(6 rows)
    
    *Объясните результат:*
Seq Scan on t_books — для GROUP BY author нужно обработать все 150000 строк, поэтому Postgres читает всю таблицу.
18. 
HashAggregate — агрегирование делается хешированием: строится хеш-таблица по ключу author, поэтому сортировка не нужна (удобно, когда вход не отсортирован).

Batches: 1 и маленькое Memory Usage означают, что хеш-агрегация поместилась в память и не “проливалась” на диск. 

Даже если есть индекс по author/title, он обычно не спасает этот запрос “магически”: Postgres всё равно должен учесть все строки, а “loose index scan / index skip scan” для MAX(...) GROUP BY ... автоматически Postgres обычно не делает.

18. Выберите первых 10 авторов:
    ```sql
    EXPLAIN ANALYZE
    SELECT DISTINCT author 
    FROM t_books 
    ORDER BY author 
    LIMIT 10;
    ```
    
    *План выполнения:*
 Limit  (cost=0.42..56.67 rows=10 width=10) (actual time=0.156..0.409 rows=10 loops=1)
   ->  Result  (cost=0.42..5625.42 rows=1000 width=10) (actual time=0.112..0.364 rows=10 loops=1)
         ->  Unique  (cost=0.42..5625.42 rows=1000 width=10) (actual time=0.111..0.362 rows=10 loops=1)
               ->  Index Only Scan using t_books_author_title_index on t_books  (cost=0.42..5250.42 rows=150000 width=10) (actual time=0.110..0.272 rows=1338 loops=1)
                     Heap Fetches: 1
 Planning Time: 0.200 ms
 Execution Time: 1.065 ms
(7 rows)

    
    *Объясните результат:*
Используется Index Only Scan по индексу (author, title), потому что запросу нужен только author (он есть в индексе), и порядок в индексе сразу подходит под ORDER BY author. 

Unique реализует DISTINCT: при скане индекса идут строки, где один и тот же author повторяется много раз (по разным книгам), поэтому узел Unique “схлопывает” дубли и оставляет уникальные значения. 

Limit позволяет остановиться рано: чтобы получить 10 уникальных авторов, PostgreSQL просмотрел 1338 индексных записей (rows=1338 у Index Only Scan), пока набрал 10 разных авторов.

Heap Fetches: 1 — почти идеальный index-only scan: 1 раз всё же пришлось сходить в таблицу для проверки видимости строки (это зависит от visibility map / VACUUM).
19. Выполните поиск и сортировку:
    ```sql
    EXPLAIN ANALYZE
    SELECT author, title 
    FROM t_books 
    WHERE author LIKE 'T%'
    ORDER BY author, title;
    ```
    
    *План выполнения:*
Sort  (cost=3100.27..3100.30 rows=14 width=21) (actual time=14.521..14.522 rows=1 loops=1)
   Sort Key: author, title
   Sort Method: quicksort  Memory: 25kB
   ->  Seq Scan on t_books  (cost=0.00..3100.00 rows=14 width=21) (actual time=14.503..14.504 rows=1 loops=1)
         Filter: ((author)::text ~~ 'T%'::text)
         Rows Removed by Filter: 149999
 Planning Time: 1.211 ms

    
    *Объясните результат:*
Seq Scan — PostgreSQL прошёл всю таблицу, потому что условие LIKE 'T%' в текущих условиях не получилось эффективно превратить в “диапазон по индексу” (поэтому индекс по (author, title) не был выбран).

Rows Removed by Filter: 149999 — столько строк проверили и отбросили фильтром.

Потом идёт Sort, потому что после Seq Scan строки не гарантированно отсортированы; сортировка дешёвая, т.к. реально вернулась всего 1 строка (rows=1), поэтому quicksort занял мало памяти.

20. Добавьте новую книгу:
    ```sql
    INSERT INTO t_books (book_id, title, author, category, is_active)
    VALUES (150001, 'Cookbook', 'Mr. Hide', NULL, true);
    COMMIT;
    ```
    
    *Результат:*
INSERT 0 1
WARNING:  there is no transaction in progress
COMMIT

21. Создайте индекс по категории:
    ```sql
    CREATE INDEX t_books_cat_idx ON t_books(category);
    ```
    
    *Результат:*
CREATE INDEX


22. Найдите книги без категории:
    ```sql
    EXPLAIN ANALYZE
    SELECT author, title 
    FROM t_books 
    WHERE category IS NULL;
    ```
    
    *План выполнения:*
 Index Scan using t_books_cat_idx on t_books  (cost=0.29..8.16 rows=1 width=21) (actual time=0.049..0.050 rows=1 loops=1)
   Index Cond: (category IS NULL)
 Planning Time: 0.348 ms
 Execution Time: 0.070 ms
(4 rows)

    
    *Объясните результат:*
Index Scan using t_books_cat_idx — PostgreSQL использует B-tree индекс по category, потому что B-tree умеет работать с условиями IS NULL / IS NOT NULL. 

Index Cond: (category IS NULL) — условие отрабатывает прямо на уровне индекса (то есть не нужно читать всю таблицу и филь

Запрос быстрый, потому что NULL-значений мало (у тебя фактически нашлась 1 строка), и индекс сразу находит нужные записи.

23. Создайте частичные индексы:
    ```sql
    DROP INDEX t_books_cat_idx;
    CREATE INDEX t_books_cat_null_idx ON t_books(category) WHERE category IS NULL;
    ```
    
    *Результат:*
DROP INDEX
CREATE INDEX

24. Повторите запрос из шага 22:
    ```sql
    EXPLAIN ANALYZE
    SELECT author, title 
    FROM t_books 
    WHERE category IS NULL;
    ```
    
    *План выполнения:*
 Index Scan using t_books_cat_null_idx on t_books  (cost=0.12..7.99 rows=1 width=21) (actual time=0.019..0.020 rows=1 loops=1)
 Planning Time: 0.368 ms
 Execution Time: 0.039 ms
(3 rows)

    
    *Объясните результат:*

Используется частичный индекс t_books_cat_null_idx (он хранит записи только для строк, где category IS NULL), поэтому он меньше и искать по нему дешевле/быстрее. 

Index Cond не показан, потому что условие category IS NULL фактически уже “вшито” в предикат частичного индекса: планировщик может использовать индекс, когда WHERE запроса логически подразумевает предикат индекса. 

Время стало чуть меньше, чем с обычным индексом по category, потому что читается меньше индексных данных.

25. Создайте частичный уникальный индекс:
    ```sql
    CREATE UNIQUE INDEX t_books_selective_unique_idx 
    ON t_books(title) 
    WHERE category = 'Science';
    
    -- Протестируйте его
    INSERT INTO t_books (book_id, title, author, category, is_active)
    VALUES (150002, 'Unique Science Book', 'Author 1', 'Science', true);
    
    -- Попробуйте вставить дубликат
    INSERT INTO t_books (book_id, title, author, category, is_active)
    VALUES (150003, 'Unique Science Book', 'Author 2', 'Science', true);
    
    -- Но можно вставить такое же название для другой категории
    INSERT INTO t_books (book_id, title, author, category, is_active)
    VALUES (150004, 'Unique Science Book', 'Author 3', 'History', true);
    ```
    
    *Результат:*
INSERT 0 1
ERROR:  duplicate key value violates unique constraint "t_books_selective_unique_idx"
DETAIL:  Key (title)=(Unique Science Book) already exists.

    
    *Объясните результат:*
CREATE UNIQUE INDEX ... WHERE category = 'Science' — это частичный уникальный индекс: он контролирует уникальность title только для строк, которые удовлетворяют предикату category = 'Science'. 

Поэтому 1-я вставка в Science прошла (INSERT 0 1), а 2-я вставка с тем же title и category='Science' упала: для “Science-подмножества” title должен быть уникальным. 

Вставка с таким же title, но с category='History', должна пройти, потому что она не попадает под предикат индекса и не проверяется этим уникальным правилом.