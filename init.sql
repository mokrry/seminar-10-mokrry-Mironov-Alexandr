CREATE TABLE t_books (
    book_id     INTEGER      NOT NULL,
    title       VARCHAR(100) NOT NULL,
    category    VARCHAR(30),
    author      VARCHAR(100) NOT NULL,
    is_active   BOOLEAN      NOT NULL,
    CONSTRAINT t_books_id_pk PRIMARY KEY (book_id)
);

-- Генерация тестовых данных
INSERT INTO t_books
SELECT
    generate_series(1, 150000) as book_id,
    'Book_' || generate_series(1, 150000) as title,
    (ARRAY['Fiction', 'Science', 'History', 'Technology', 'Art'])[ceil(random()*5)] as category,
    'Author_' || ceil(random()*1000) as author,
    random() < 0.6 as is_active;

-- Добавление конкретных книг для тестирования
UPDATE t_books SET
    title = 'Oracle Core',
    category = 'Databases',
    author = 'Jonathan Lewis',
    is_active = true
WHERE book_id = 3001;

UPDATE t_books SET
    title = 'Expert PostgreSQL Architecture',
    category = 'Databases',
    author = 'Tom Lane',
    is_active = true
WHERE book_id = 2025;

UPDATE t_books SET
    title = 'SQL and Relational Theory',
    category = 'Databases',
    author = 'C.J. Date',
    is_active = true
WHERE book_id = 190;