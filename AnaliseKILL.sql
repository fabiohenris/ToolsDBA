/*
********************************************************
Autor :  Fabio Henrique da Silva
linkedin: https://www.linkedin.com/in/fabio-henriques/
Assunto: Scrip para analise de KILL dentro do banco de dados

*/

-- últimas 6h procurando por eventos de KILL no Error Log
DECLARE @desde DATETIME = DATEADD(HOUR,-24,GETDATE());

EXEC xp_readerrorlog 0, 1, N'was killed by',  NULL, @desde, NULL, N'desc';  -- inglês
EXEC xp_readerrorlog 0, 1, N'killed process', NULL, @desde, NULL, N'desc';  -- variação
-- se seu SQL estiver em PT-BR e logar traduzido, tente:
EXEC xp_readerrorlog 0, 1, N'foi morto',      NULL, @desde, NULL, N'desc';
