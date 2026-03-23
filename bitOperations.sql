-- Спецификация пакета
CREATE OR REPLACE PACKAGE bitOperations IS
    FUNCTION decimalToBinary(n NUMBER) RETURN VARCHAR2;  -- перевод из десятичного в двоичное
    FUNCTION binaryToDecimal(b_in VARCHAR2) RETURN NUMBER;  -- перевод из двоичного в десятичное
    
    FUNCTION bit_and(a NUMBER, b NUMBER) RETURN NUMBER;  -- побитовое AND
    FUNCTION bit_or(a NUMBER, b NUMBER) RETURN NUMBER;  -- побитовое OR
    FUNCTION bit_xor(a NUMBER, b NUMBER) RETURN NUMBER;  -- побитовое XOR
    FUNCTION bit_not(a NUMBER) RETURN NUMBER;  -- побитовое NOT
    
    -- циклический сдвиг влево и вправо на заданное кол-во двоичных разрядов для десятичных чисел
    FUNCTION rotate_right(n NUMBER, shift NUMBER) RETURN NUMBER;
    FUNCTION rotate_left(n NUMBER, shift NUMBER) RETURN NUMBER;
END bitOperations;
/

-- Тело пакета
CREATE OR REPLACE PACKAGE BODY bitOperations IS

    -- Приватная функция проверки десятичного числа
    FUNCTION checkDecimal(n NUMBER) RETURN BOOLEAN IS
    BEGIN
        -- Проверка на NULL
        IF n IS NULL THEN
            RETURN FALSE;
        END IF;

        -- Проверка диапазона целой части для 16-бит signed (-32768..32767)
        IF n < -32768 OR n >= 32768 THEN
            RETURN FALSE;
        END IF;

        -- Всё корректно
        RETURN TRUE;

    EXCEPTION
        WHEN OTHERS THEN
            RETURN FALSE;  -- неожиданные ошибки
    END checkDecimal;
    
    -- Приватная функция проверки бинарной строки
    FUNCTION checkBinary(b_in VARCHAR2) RETURN BOOLEAN IS
        v_b VARCHAR2(100);
    BEGIN
        IF b_in IS NULL OR TRIM(b_in) = '' THEN
            RETURN FALSE;
        END IF;
    
        -- локальная копия с обрезанными пробелами
        v_b := TRIM(b_in);
    
        -- проверка через регулярное выражение
        IF REGEXP_LIKE(v_b, '^[01]{1,16}(\.[01]{1,16})?$') THEN
            RETURN TRUE;
        ELSE
            RETURN FALSE;
        END IF;
    
    EXCEPTION
        WHEN OTHERS THEN
            RETURN FALSE;
    END checkBinary;

    -- Приватная функция
    -- проверка корректности ввода происходит в вызываемой public-функции
    FUNCTION decimalToBinary_raw(n NUMBER) RETURN VARCHAR2 IS
        c_total_bits CONSTANT PLS_INTEGER := 32;
        c_frac_bits  CONSTANT PLS_INTEGER := 16;
        c_scale      CONSTANT NUMBER := POWER(2, c_frac_bits);
        c_two_pow_32 CONSTANT NUMBER := POWER(2, c_total_bits);

        v_scaled   NUMBER;
        v_unsigned NUMBER;
        v_result   VARCHAR2(32);
        v_bit_num  NUMBER;
    BEGIN
        IF n IS NULL THEN
            RETURN NULL;
        END IF;

        -- Q16.16: масштабируем число
        v_scaled := ROUND(n * c_scale, 0);

        -- Преобразуем signed -> unsigned 32-bit
        IF v_scaled < 0 THEN
            v_unsigned := v_scaled + c_two_pow_32;
        ELSE
            v_unsigned := v_scaled;
        END IF;

        -- Собираем 32 бита слева направо
        v_result := '';
        FOR i IN 1 .. c_total_bits LOOP
            v_bit_num := MOD(v_unsigned, 2);

            IF v_bit_num = 1 THEN
                v_result := '1' || v_result;
            ELSE
                v_result := '0' || v_result;
            END IF;

            v_unsigned := TRUNC(v_unsigned / 2);
        END LOOP;

        RETURN v_result;
    END decimalToBinary_raw;
    
    -- Приватная функция: raw 32-бита -> "целая.дробная"
    -- проверка корректности ввода происходит в вызываемой public-функции
    FUNCTION rawBinaryToBinary(raw_bin VARCHAR2) RETURN VARCHAR2 IS
        c_total_bits CONSTANT PLS_INTEGER := 32;
        c_int_bits   CONSTANT PLS_INTEGER := 16;
        c_frac_bits  CONSTANT PLS_INTEGER := 16;
    
        v_int_bin      VARCHAR2(16);
        v_frac_bin     VARCHAR2(16);
        v_int_trimmed  VARCHAR2(16);
        v_frac_trimmed VARCHAR2(16);
        v_result       VARCHAR2(100);
    BEGIN    
        -- Разделяем на целую и дробную части
        v_int_bin  := SUBSTR(raw_bin, 1, c_int_bits);
        v_frac_bin := SUBSTR(raw_bin, c_int_bits + 1, c_frac_bits);
    
        -- Обрезаем ведущие нули в целой части
        IF SUBSTR(v_int_bin, 1, 1) = '1' THEN
            v_int_trimmed := v_int_bin;  -- оставляем отрицательные без обрезки
        ELSE
            v_int_trimmed := LTRIM(v_int_bin, '0');
            IF v_int_trimmed IS NULL OR v_int_trimmed = '' THEN
                v_int_trimmed := '0';
            END IF;
        END IF;
    
        -- Обрезаем хвостовые нули в дробной части
        v_frac_trimmed := RTRIM(v_frac_bin, '0');
    
        -- Формируем строку с точкой, если есть дробная часть
        IF v_frac_trimmed IS NULL OR v_frac_trimmed = '' THEN
            v_result := v_int_trimmed;
        ELSE
            v_result := v_int_trimmed || '.' || v_frac_trimmed;
        END IF;
    
        RETURN v_result;
    END rawBinaryToBinary;
    
    -- Перевод из десятичного в двоичное
    FUNCTION decimalToBinary(n NUMBER) RETURN VARCHAR2 IS
        v_bin VARCHAR2(32);
    BEGIN
        IF n IS NULL THEN
            RETURN NULL;
        END IF;
        
         -- Проверка корректности числа
        IF NOT checkDecimal(n) THEN
            RAISE_APPLICATION_ERROR(
                -20051,
                'Invalid input for decimalToBinary: ' || n
            );
        END IF;
    
        -- Получаем 32-битное представление Q16.16
        v_bin := decimalToBinary_raw(n);
    
        -- Формируем строку с точкой через приватную функцию
        RETURN rawBinaryToBinary(v_bin);
    END decimalToBinary;
    
    -- Бинарное в десятичное
    FUNCTION binaryToDecimal(b_in VARCHAR2) RETURN NUMBER IS
        v_b        VARCHAR2(100);
        v_int_bin  VARCHAR2(16);
        v_frac_bin VARCHAR2(16);
        v_int_num  NUMBER := 0;
        v_frac_num NUMBER := 0;
        v_result   NUMBER;
        c_int_bits CONSTANT PLS_INTEGER := 16;
    BEGIN
        -- Проверка корректности бинарной строки
        IF NOT checkBinary(b_in) THEN
            RAISE_APPLICATION_ERROR(
                -20051,
                'Invalid input for binaryToDecimal: ' || b_in
            );
        END IF;
    
        -- локальная копия без пробелов
        v_b := TRIM(b_in);
    
        -- Разделяем на целую и дробную части
        IF INSTR(v_b, '.') > 0 THEN
            v_int_bin  := SUBSTR(v_b, 1, INSTR(v_b, '.') - 1);
            v_frac_bin := SUBSTR(v_b, INSTR(v_b, '.') + 1);
        ELSE
            v_int_bin  := v_b;
            v_frac_bin := NULL;
        END IF;
    
        -- Дополняем целую часть до 16 бит слева нулями
        v_int_bin := LPAD(v_int_bin, c_int_bits, '0');
    
        -- Если старший бит = 1 -> отрицательное число (двухкомплемент)
        IF SUBSTR(v_int_bin, 1, 1) = '1' THEN
            -- Инвертируем биты
            FOR i IN 1 .. LENGTH(v_int_bin) LOOP
                IF SUBSTR(v_int_bin, i, 1) = '0' THEN
                    v_int_num := v_int_num * 2 + 1;
                ELSE
                    v_int_num := v_int_num * 2 + 0;
                END IF;
            END LOOP;
            -- Добавляем 1 и делаем отрицательным
            v_int_num := -(v_int_num + 1);
        ELSE
            -- Положительное число
            FOR i IN 1 .. LENGTH(v_int_bin) LOOP
                v_int_num := v_int_num * 2 + TO_NUMBER(SUBSTR(v_int_bin, i, 1));
            END LOOP;
        END IF;
    
        -- Перевод дробной части из бинарного
        IF v_frac_bin IS NOT NULL THEN
            FOR i IN 1 .. LENGTH(v_frac_bin) LOOP
                v_frac_num := v_frac_num + TO_NUMBER(SUBSTR(v_frac_bin, i, 1)) / POWER(2, i);
            END LOOP;
        END IF;
    
        -- Складываем целую и дробную части
        v_result := v_int_num + v_frac_num;
    
        RETURN v_result;
    END binaryToDecimal;
    
    -- Побитовое AND
    FUNCTION bit_and(a NUMBER, b NUMBER) 
    RETURN NUMBER IS
        v_bin_a       VARCHAR2(32);
        v_bin_b       VARCHAR2(32);
        v_bin_result  VARCHAR2(32);
        v_result      NUMBER;
    BEGIN
        -- Если хоть один NULL, возвращаем NULL
        IF a IS NULL OR b IS NULL THEN
            RETURN NULL;
        END IF;
        
        IF NOT checkDecimal(a) OR NOT checkDecimal(b) THEN
            RAISE_APPLICATION_ERROR(-20050, 'Input out of range for bit operation');
        END IF;
    
        -- Получаем 32-битное представление обоих чисел
        v_bin_a := decimalToBinary_raw(a);
        v_bin_b := decimalToBinary_raw(b);
    
        -- Побитовое И
        v_bin_result := '';
        FOR i IN 1 .. 32 LOOP
            IF SUBSTR(v_bin_a, i, 1) = '1' AND SUBSTR(v_bin_b, i, 1) = '1' THEN
                v_bin_result := v_bin_result || '1';
            ELSE
                v_bin_result := v_bin_result || '0';
            END IF;
        END LOOP;
    
        -- Преобразуем "сырые" 32 бита через rawBinaryToBinary в корректную строку
        v_result := binaryToDecimal(rawBinaryToBinary(v_bin_result));
    
        RETURN v_result;
    END bit_and;
    
    -- Побитовое OR
    FUNCTION bit_or(a NUMBER, b NUMBER) 
    RETURN NUMBER IS
        v_bin_a VARCHAR2(32);
        v_bin_b VARCHAR2(32);
        v_bin_result VARCHAR2(32);
        v_result NUMBER;
    BEGIN
        IF a IS NULL OR b IS NULL THEN
            RETURN NULL;
        END IF;
        
        IF NOT checkDecimal(a) OR NOT checkDecimal(b) THEN
            RAISE_APPLICATION_ERROR(-20050, 'Input out of range for bit operation');
        END IF;
    
        -- Получаем 32-битное представление обоих чисел
        v_bin_a := decimalToBinary_raw(a);
        v_bin_b := decimalToBinary_raw(b);
    
        -- Побитовое ИЛИ
        v_bin_result := '';
        FOR i IN 1..LENGTH(v_bin_a) LOOP
            IF SUBSTR(v_bin_a, i, 1) = '1' OR SUBSTR(v_bin_b, i, 1) = '1' THEN
                v_bin_result := v_bin_result || '1';
            ELSE
                v_bin_result := v_bin_result || '0';
            END IF;
        END LOOP;
    
        -- Преобразуем результат обратно в число
        v_result := binaryToDecimal(rawBinaryToBinary(v_bin_result));
    
        RETURN v_result;
    END bit_or;

    -- Побитовое XOR
    FUNCTION bit_xor(a NUMBER, b NUMBER)
    RETURN NUMBER IS
        v_bin_a       VARCHAR2(32);
        v_bin_b       VARCHAR2(32);
        v_bin_result  VARCHAR2(32);
        v_result      NUMBER;
    BEGIN
        IF a IS NULL OR b IS NULL THEN
            RETURN NULL;
        END IF;
        
        IF NOT checkDecimal(a) OR NOT checkDecimal(b) THEN
            RAISE_APPLICATION_ERROR(-20050, 'Input out of range for bit operation');
        END IF;
    
        -- Получаем 32-битное представление обоих чисел
        v_bin_a := decimalToBinary_raw(a);
        v_bin_b := decimalToBinary_raw(b);
    
        -- Побитовое XOR
        v_bin_result := '';
        FOR i IN 1..LENGTH(v_bin_a) LOOP
            IF SUBSTR(v_bin_a, i, 1) != SUBSTR(v_bin_b, i, 1) THEN
                v_bin_result := v_bin_result || '1';
            ELSE
                v_bin_result := v_bin_result || '0';
            END IF;
        END LOOP;
    
        -- Преобразуем результат обратно в число через rawBinaryToBinary
        v_result := binaryToDecimal(rawBinaryToBinary(v_bin_result));
    
        RETURN v_result;
    END bit_xor;
    
    -- Побитовое NOT
    FUNCTION bit_not(a NUMBER) RETURN NUMBER IS
        v_bin_a       VARCHAR2(32);
        v_bin_result  VARCHAR2(32);
        v_result      NUMBER;
    BEGIN
        IF a IS NULL THEN
            RETURN NULL;
        END IF;
        
        IF NOT checkDecimal(a) THEN
            RAISE_APPLICATION_ERROR(-20050, 'Input out of range for bit operation');
        END IF;
    
        -- Получаем 32-битное представление числа
        v_bin_a := decimalToBinary_raw(a);
    
        -- Инвертируем каждый бит
        v_bin_result := '';
        FOR i IN 1 .. LENGTH(v_bin_a) LOOP
            IF SUBSTR(v_bin_a, i, 1) = '1' THEN
                v_bin_result := v_bin_result || '0';
            ELSE
                v_bin_result := v_bin_result || '1';
            END IF;
        END LOOP;
    
        -- Преобразуем обратно в число
        v_result := binaryToDecimal(rawBinaryToBinary(v_bin_result));
    
        RETURN v_result;
    END bit_not;
    
    -- Циклический сдвиг влево
    FUNCTION rotate_left(n NUMBER, shift NUMBER) RETURN NUMBER IS
        v_bin VARCHAR2(32);
        v_shifted VARCHAR2(32);
        v_result NUMBER;
        s NUMBER;
    BEGIN
        IF n IS NULL OR shift IS NULL THEN
            RETURN NULL;
        END IF;
        
        IF shift < 0 OR shift != TRUNC(shift) THEN
            RAISE_APPLICATION_ERROR(-20052, 'Shift must be a non-negative integer');
        END IF;
        
        IF NOT checkDecimal(n) THEN
            RAISE_APPLICATION_ERROR(-20050, 'Input out of range for bit operation');
        END IF;
    
        s := MOD(shift, 32);
        v_bin := decimalToBinary_raw(n);
    
        -- Циклический сдвиг влево (при s=0 работает корректно)
        v_shifted := SUBSTR(v_bin, s + 1) || SUBSTR(v_bin, 1, s);
    
        v_result := binaryToDecimal(rawBinaryToBinary(v_shifted));
        RETURN v_result;
    END rotate_left;
    
    -- Циклический сдвиг вправо
    FUNCTION rotate_right(n NUMBER, shift NUMBER) RETURN NUMBER IS
        v_bin VARCHAR2(32);
        v_shifted VARCHAR2(32);
        v_result NUMBER;
        s NUMBER;
    BEGIN
        IF n IS NULL OR shift IS NULL THEN
            RETURN NULL;
        END IF;
        
        IF shift < 0 OR shift != TRUNC(shift) THEN
            RAISE_APPLICATION_ERROR(-20052, 'Shift must be a non-negative integer');
        END IF;
        
        IF NOT checkDecimal(n) THEN
            RAISE_APPLICATION_ERROR(-20050, 'Input out of range for bit operation');
        END IF;
    
        s := MOD(shift, 32);
        v_bin := decimalToBinary_raw(n);
    
        -- Циклический сдвиг вправо (обрабатываем s=0)
        IF s = 0 THEN
            v_shifted := v_bin;
        ELSE
            v_shifted := SUBSTR(v_bin, 33 - s) || SUBSTR(v_bin, 1, 32 - s);
        END IF;
    
        v_result := binaryToDecimal(rawBinaryToBinary(v_shifted));
        RETURN v_result;
    END rotate_right;

END bitOperations;
