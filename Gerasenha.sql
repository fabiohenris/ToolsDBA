/*
********************************************************
Autor :  Fabio Henrique da Silva
linkedin: https://www.linkedin.com/in/fabio-henriques/
Assunto: Gerador de senha dinamico  
*/

DECLARE @Password NVARCHAR(100) = '';

-- Conjuntos de caracteres
DECLARE @Upper   NVARCHAR(26) = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ';
DECLARE @Lower   NVARCHAR(26) = 'abcdefghijklmnopqrstuvwxyz';
DECLARE @Numbers NVARCHAR(10) = '0123456789';
DECLARE @Special NVARCHAR(20) = '!@#$%^&*()-_=+[]{}|;:,.<>?/';
DECLARE @Length  NVARCHAR(2) = '32'; -- Quantidade de caractere ,8,16,32,64,128... etc

DECLARE @All NVARCHAR(200) = @Upper + @Lower + @Numbers + @Special;

-- Garante pelo menos 1 de cada tipo
SET @Password += SUBSTRING(@Upper,   ABS(CHECKSUM(NEWID())) % LEN(@Upper)   + 1, 1);
SET @Password += SUBSTRING(@Lower,   ABS(CHECKSUM(NEWID())) % LEN(@Lower)   + 1, 1);
SET @Password += SUBSTRING(@Numbers, ABS(CHECKSUM(NEWID())) % LEN(@Numbers) + 1, 1);
SET @Password += SUBSTRING(@Special, ABS(CHECKSUM(NEWID())) % LEN(@Special) + 1, 1);

-- Montgem da senha.
WHILE LEN(@Password) < @Length
    SET @Password += SUBSTRING(@All, ABS(CHECKSUM(NEWID())) % LEN(@All) + 1, 1);

-- Embaralhar a senha para evitar padrão fixo
;WITH CTE AS (
    SELECT SUBSTRING(@Password, v.number+1, 1) AS ch
    FROM master..spt_values v
    WHERE v.type='P' AND v.number < LEN(@Password)
)
SELECT Password = STRING_AGG(ch, '')
FROM CTE
ORDER BY NEWID();
