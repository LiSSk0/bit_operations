CREATE OR REPLACE PACKAGE bitOperations IS
    FUNCTION decimalToBinary(n NUMBER) RETURN VARCHAR2; 
    FUNCTION binaryToDecimal(b_in VARCHAR2) RETURN NUMBER; 
    
    FUNCTION bit_and(a NUMBER, b NUMBER) RETURN NUMBER;
    FUNCTION bit_or(a NUMBER, b NUMBER) RETURN NUMBER;
    FUNCTION bit_xor(a NUMBER, b NUMBER) RETURN NUMBER;
    FUNCTION bit_not(a NUMBER) RETURN NUMBER; 
    
    FUNCTION rotate_right(n NUMBER, shift NUMBER) RETURN NUMBER;
    FUNCTION rotate_left(n NUMBER, shift NUMBER) RETURN NUMBER;
END bitOperations;
/

CREATE OR REPLACE PACKAGE BODY bitOperations IS

    FUNCTION checkDecimal(n NUMBER) RETURN BOOLEAN IS
    BEGIN
        IF n IS NULL THEN
            RETURN FALSE;
        END IF;

        IF n < -32768 OR n >= 32768 THEN
            RETURN FALSE;
        END IF;

        RETURN TRUE;

    EXCEPTION
        WHEN OTHERS THEN
            RETURN FALSE;
    END checkDecimal;
    
    FUNCTION checkBinary(b_in VARCHAR2) RETURN BOOLEAN IS
        v_b VARCHAR2(100);
    BEGIN
        IF b_in IS NULL OR TRIM(b_in) = '' THEN
            RETURN FALSE;
        END IF;
    
        v_b := TRIM(b_in);
    
        IF REGEXP_LIKE(v_b, '^[01]{1,16}(\.[01]{1,16})?$') THEN
            RETURN TRUE;
        ELSE
            RETURN FALSE;
        END IF;
    
    EXCEPTION
        WHEN OTHERS THEN
            RETURN FALSE;
    END checkBinary;

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

        v_scaled := ROUND(n * c_scale, 0);
        
        IF v_scaled < 0 THEN
            v_unsigned := v_scaled + c_two_pow_32;
        ELSE
            v_unsigned := v_scaled;
        END IF;

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
        v_int_bin  := SUBSTR(raw_bin, 1, c_int_bits);
        v_frac_bin := SUBSTR(raw_bin, c_int_bits + 1, c_frac_bits);
    
        IF SUBSTR(v_int_bin, 1, 1) = '1' THEN
            v_int_trimmed := v_int_bin;
        ELSE
            v_int_trimmed := LTRIM(v_int_bin, '0');
            IF v_int_trimmed IS NULL OR v_int_trimmed = '' THEN
                v_int_trimmed := '0';
            END IF;
        END IF;
    
        v_frac_trimmed := RTRIM(v_frac_bin, '0');
    
        IF v_frac_trimmed IS NULL OR v_frac_trimmed = '' THEN
            v_result := v_int_trimmed;
        ELSE
            v_result := v_int_trimmed || '.' || v_frac_trimmed;
        END IF;
    
        RETURN v_result;
    END rawBinaryToBinary;
    
    FUNCTION decimalToBinary(n NUMBER) RETURN VARCHAR2 IS
        v_bin VARCHAR2(32);
    BEGIN
        IF n IS NULL THEN
            RETURN NULL;
        END IF;
        
        IF NOT checkDecimal(n) THEN
            RAISE_APPLICATION_ERROR(
                -20051,
                'Invalid input for decimalToBinary: ' || n
            );
        END IF;
    
        v_bin := decimalToBinary_raw(n);
    
        RETURN rawBinaryToBinary(v_bin);
    END decimalToBinary;
    
    FUNCTION binaryToDecimal(b_in VARCHAR2) RETURN NUMBER IS
        v_b        VARCHAR2(100);
        v_int_bin  VARCHAR2(16);
        v_frac_bin VARCHAR2(16);
        v_int_num  NUMBER := 0;
        v_frac_num NUMBER := 0;
        v_result   NUMBER;
        c_int_bits CONSTANT PLS_INTEGER := 16;
    BEGIN
        IF NOT checkBinary(b_in) THEN
            RAISE_APPLICATION_ERROR(
                -20051,
                'Invalid input for binaryToDecimal: ' || b_in
            );
        END IF;
    
        v_b := TRIM(b_in);
    
        IF INSTR(v_b, '.') > 0 THEN
            v_int_bin  := SUBSTR(v_b, 1, INSTR(v_b, '.') - 1);
            v_frac_bin := SUBSTR(v_b, INSTR(v_b, '.') + 1);
        ELSE
            v_int_bin  := v_b;
            v_frac_bin := NULL;
        END IF;
    
        v_int_bin := LPAD(v_int_bin, c_int_bits, '0');
    
        IF SUBSTR(v_int_bin, 1, 1) = '1' THEN
            FOR i IN 1 .. LENGTH(v_int_bin) LOOP
                IF SUBSTR(v_int_bin, i, 1) = '0' THEN
                    v_int_num := v_int_num * 2 + 1;
                ELSE
                    v_int_num := v_int_num * 2 + 0;
                END IF;
            END LOOP;
            v_int_num := -(v_int_num + 1);
        ELSE
            FOR i IN 1 .. LENGTH(v_int_bin) LOOP
                v_int_num := v_int_num * 2 + TO_NUMBER(SUBSTR(v_int_bin, i, 1));
            END LOOP;
        END IF;
    
        IF v_frac_bin IS NOT NULL THEN
            FOR i IN 1 .. LENGTH(v_frac_bin) LOOP
                v_frac_num := v_frac_num + TO_NUMBER(SUBSTR(v_frac_bin, i, 1)) / POWER(2, i);
            END LOOP;
        END IF;
    
        v_result := v_int_num + v_frac_num;
    
        RETURN v_result;
    END binaryToDecimal;
    
    FUNCTION bit_and(a NUMBER, b NUMBER) 
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
    
        v_bin_a := decimalToBinary_raw(a);
        v_bin_b := decimalToBinary_raw(b);
    
        v_bin_result := '';
        FOR i IN 1 .. 32 LOOP
            IF SUBSTR(v_bin_a, i, 1) = '1' AND SUBSTR(v_bin_b, i, 1) = '1' THEN
                v_bin_result := v_bin_result || '1';
            ELSE
                v_bin_result := v_bin_result || '0';
            END IF;
        END LOOP;
    
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
    
        v_bin_a := decimalToBinary_raw(a);
        v_bin_b := decimalToBinary_raw(b);
    
        v_bin_result := '';
        FOR i IN 1..LENGTH(v_bin_a) LOOP
            IF SUBSTR(v_bin_a, i, 1) = '1' OR SUBSTR(v_bin_b, i, 1) = '1' THEN
                v_bin_result := v_bin_result || '1';
            ELSE
                v_bin_result := v_bin_result || '0';
            END IF;
        END LOOP;
    
        v_result := binaryToDecimal(rawBinaryToBinary(v_bin_result));
    
        RETURN v_result;
    END bit_or;

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
    
        v_bin_a := decimalToBinary_raw(a);
        v_bin_b := decimalToBinary_raw(b);
    
        v_bin_result := '';
        FOR i IN 1..LENGTH(v_bin_a) LOOP
            IF SUBSTR(v_bin_a, i, 1) != SUBSTR(v_bin_b, i, 1) THEN
                v_bin_result := v_bin_result || '1';
            ELSE
                v_bin_result := v_bin_result || '0';
            END IF;
        END LOOP;
    
        v_result := binaryToDecimal(rawBinaryToBinary(v_bin_result));
    
        RETURN v_result;
    END bit_xor;
    
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
    
        v_bin_a := decimalToBinary_raw(a);
    
        v_bin_result := '';
        FOR i IN 1 .. LENGTH(v_bin_a) LOOP
            IF SUBSTR(v_bin_a, i, 1) = '1' THEN
                v_bin_result := v_bin_result || '0';
            ELSE
                v_bin_result := v_bin_result || '1';
            END IF;
        END LOOP;
    
        v_result := binaryToDecimal(rawBinaryToBinary(v_bin_result));
    
        RETURN v_result;
    END bit_not;
    
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
    
        v_shifted := SUBSTR(v_bin, s + 1) || SUBSTR(v_bin, 1, s);
    
        v_result := binaryToDecimal(rawBinaryToBinary(v_shifted));
        RETURN v_result;
    END rotate_left;
    
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
    
        IF s = 0 THEN
            v_shifted := v_bin;
        ELSE
            v_shifted := SUBSTR(v_bin, 33 - s) || SUBSTR(v_bin, 1, 32 - s);
        END IF;
    
        v_result := binaryToDecimal(rawBinaryToBinary(v_shifted));
        RETURN v_result;
    END rotate_right;

END bitOperations;

