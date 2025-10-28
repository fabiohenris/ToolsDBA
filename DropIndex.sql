/*
********************************************************
Autor :  Fabio Henrique da Silva
linkedin: https://www.linkedin.com/in/fabio-henriques/
Assunto: Query para identidicar quando um Index não esta sendo mais utilizado, gerando o comando para exclusão do mesmo .
*/


----------------------------------------------------------

DECLARE @Dias INT = 30;  -- quantidade de dias de corte
DECLARE @Corte DATETIME = DATEADD(DAY, -@Dias, GETDATE());

;WITH idx AS (
    SELECT 
        i.object_id, i.index_id, i.name AS NomeIndice,
        s.name AS NomeEsquema, o.name AS NomeTabela,
        i.is_primary_key, i.is_unique, i.is_unique_constraint,
        i.is_hypothetical, i.is_disabled
    FROM sys.indexes i
    JOIN sys.objects o ON o.object_id = i.object_id AND o.type = 'U'
    JOIN sys.schemas s ON s.schema_id = o.schema_id
),
uso AS (
    SELECT 
        u.object_id, u.index_id,
        u.user_seeks     AS Buscas,
        u.user_scans     AS LeituraCompleta,
        u.user_lookups   AS Lookups,
        u.user_updates   AS Atualizacoes,
        u.last_user_seek   AS UltimaBusca,
        u.last_user_scan   AS UltimaLeituraCompleta,
        u.last_user_lookup AS UltimoLookup
    FROM sys.dm_db_index_usage_stats u
    WHERE u.database_id = DB_ID()
),
tamanho AS (
    SELECT 
        p.object_id, p.index_id,
        SUM(p.reserved_page_count) * 8.0/1024 AS EspacoReservadoMB,
        SUM(p.used_page_count)     * 8.0/1024 AS EspacoUsadoMB,
        SUM(p.row_count) AS [QtdLinhas]
    FROM sys.dm_db_partition_stats p
    GROUP BY p.object_id, p.index_id
),
final AS (
    SELECT 
        idx.NomeEsquema, idx.NomeTabela, idx.NomeIndice,
        idx.index_id, 
        ISNULL(u.Buscas,0)            AS TotalBuscas,
        ISNULL(u.LeituraCompleta,0)   AS TotalLeiturasCompletas,
        ISNULL(u.Lookups,0)           AS TotalLookups,
        u.UltimaBusca, u.UltimaLeituraCompleta, u.UltimoLookup,
        t.[QtdLinhas], t.EspacoReservadoMB, t.EspacoUsadoMB,
        ComandoDrop = 
           'DROP INDEX ' + QUOTENAME(idx.NomeIndice) + ' ON ' 
           + QUOTENAME(idx.NomeEsquema) + '.' + QUOTENAME(idx.NomeTabela) + ';'
    FROM idx
    LEFT JOIN uso u 
      ON u.object_id = idx.object_id AND u.index_id = idx.index_id
    LEFT JOIN tamanho t
      ON t.object_id = idx.object_id AND t.index_id = idx.index_id
    WHERE 
          idx.index_id > 1                         -- exclui heap (0) e índice clustered (1)
      AND idx.is_primary_key = 0                   -- não considerar PK
      AND idx.is_unique_constraint = 0             -- não considerar constraints UNIQUE
      AND idx.is_hypothetical = 0                  -- não considerar índices hipotéticos
      AND idx.is_disabled = 0                      -- não considerar índices desabilitados
      AND (
            (u.UltimaBusca           IS NULL OR u.UltimaBusca           < @Corte) AND
            (u.UltimaLeituraCompleta IS NULL OR u.UltimaLeituraCompleta < @Corte) AND
            (u.UltimoLookup          IS NULL OR u.UltimoLookup          < @Corte)
          )
)
SELECT *
FROM final
ORDER BY EspacoReservadoMB DESC, NomeEsquema, NomeTabela, NomeIndice;
