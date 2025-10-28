/*
********************************************************
Autor :  Fabio Henrique da Silva
linkedin: https://www.linkedin.com/in/fabio-henriques/
Assunto: Scrip para auditoria de Acessos , usuarios de instancias VS Usuarios de AD.
  Conseguimos ter acesso aos dados como (Nome, UltimoAcesso 'Aproximadamente', tipo de roles, permissões , tipo do usuarios, formato hash e hash da senha . 
Blog que usei para referencia: https://dirceuresende.com/blog/sql-server-como-saber-a-data-do-ultimo-login-de-um-usuario/
*/

/*
========================================================================
   PARTE 1: Coleta de Permissões de Bancos de Dados
========================================================================
*/

-- 0. Garante que a tabela temporária de coleta não exista
IF OBJECT_ID('tempdb..#DBAcessos') IS NOT NULL
    DROP TABLE #DBAcessos;

-- Cria a tabela para armazenar os resultados
CREATE TABLE #DBAcessos (
    server_principal_sid VARBINARY(85),    -- SID do Login (para o JOIN)
    database_name NVARCHAR(128),          -- Nome do Banco
    database_principal_name NVARCHAR(128),-- Nome do Usuário (dentro do banco)
    database_roles NVARCHAR(MAX)          -- Roles (ex: db_owner, db_datareader)
);

-- Declara o SQL dinâmico que será executado em cada banco
DECLARE @db_perm_sql NVARCHAR(MAX);
SET @db_perm_sql = N'
    USE [?]; -- O placeholder [?] é substituído pelo nome de cada banco
    
    -- Insere os mapeamentos de usuário e suas roles de banco de dados
    INSERT INTO #DBAcessos (server_principal_sid, database_name, database_principal_name, database_roles)
    SELECT
        dp.sid AS server_principal_sid,
        DB_NAME() AS database_name,
        dp.name AS database_principal_name,
        ISNULL(STRING_AGG(dr.name, '', ''), ''public'') AS database_roles
        
    FROM
        sys.database_principals AS dp
    -- Junta com as roles do banco
    LEFT JOIN
        sys.database_role_members AS drm ON dp.principal_id = drm.member_principal_id
    LEFT JOIN
        sys.database_principals AS dr ON drm.role_principal_id = dr.principal_id
    WHERE
        dp.type IN (''S'', ''U'', ''G'') -- Usuários SQL, Windows e Grupos
        AND dp.sid IS NOT NULL
        AND dp.sid NOT IN (0x00, 0x01) -- Exclui ''dbo'' e ''guest'' genéricos
    GROUP BY
        dp.sid, dp.name;
';

-- Executo o SQL dinâmico para cada banco de dados na instância
-- O try/catch ignora bancos de dados offline, inacessíveis, etc.
BEGIN TRY
    EXEC sp_msforeachdb @db_perm_sql;
END TRY
BEGIN CATCH
    PRINT N'Aviso: Alguns bancos de dados não puderam ser consultados (ex: offline ou em restauração).';
END CATCH;


/*
========================================================================
   PARTE 2: Query de Auditoria Principal (Modificada)
========================================================================
*/

-- 1. Coleta todos os logins de usuário (SQL, Windows e Grupos)
WITH ServerPrincipals AS (
    SELECT
        principal_id,
        sid, -- Adicionado SID para o JOIN com a tabela de permissões
        name AS Nome,
        type,
        type_desc,
        CASE
            WHEN type IN ('U', 'G') THEN 'Usuario de AD'
            WHEN type = 'S' THEN 'Usuario de Instancia'
            ELSE type_desc
        END AS [Usuario de AD ou de Instancia]
    FROM
        sys.server_principals
    WHERE
        type IN ('S', 'U', 'G') -- Filtra por SQL Logins, Windows Logins e Windows Groups
        AND sid != 0x01 -- Exclui o login 'sa' padrão (SID 0x01)
        AND name NOT LIKE '##%' -- Exclui contas de sistema internas
),

-- 2. Encontra a hora de login das sessões *atualmente ativas*
ActiveSessions AS (
    SELECT
        login_name,
        MAX(login_time) AS UltimoAcessoSessaoAtiva
    FROM
        sys.dm_exec_sessions
    GROUP BY
        login_name
),

-- 3. Agrega as Server Roles
ServerRoles AS (
    SELECT
        m.member_principal_id,
        STRING_AGG(r.name, ', ') AS [Tipo de Role]
    FROM
        sys.server_role_members AS m
    JOIN
        sys.server_principals AS r ON m.role_principal_id = r.principal_id
    GROUP BY
        m.member_principal_id
),

-- 4. Agrega permissões explícitas no *nível do servidor*
ServerPermissions AS (
    SELECT
        grantee_principal_id,
        STRING_AGG(CONCAT(permission_name, ' (', state_desc, ')'), '; ') AS [Permissoes]
    FROM
        sys.server_permissions
    WHERE
        class = 100 -- 100 = Nível do Servidor
    GROUP BY
        grantee_principal_id
),

-- 5. [NOVA CTE] Agrega os resultados da tabela temporária #DBAcessos
DatabaseAccess AS (
    SELECT
        server_principal_sid,
        STRING_AGG(
            CONCAT(database_name, ' (User: ', database_principal_name, ', Roles: ', database_roles, ')'),
            
            '; ' -- Separador entre bancos
        ) WITHIN GROUP (ORDER BY database_name) AS [Acesso_Bancos_de_Dados]
    FROM
        #DBAcessos
    GROUP BY
        server_principal_sid
)

-- 6. Junta todas as informações (Final)
SELECT
    p.Nome,
    CASE
        WHEN p.type = 'S' THEN CONVERT(DATETIME, LOGINPROPERTY(p.Nome, 'LastLoginTime'))
        ELSE s.UltimoAcessoSessaoAtiva
    END AS [Ultimo Acesso (Aproximado)],
    ISNULL(r.[Tipo de Role], 'public') AS [Tipo de Role (Servidor)],
    ISNULL(pe.Permissoes, 'Nenhuma permissão explícita no servidor') AS [Permissoes (Servidor)],
    ISNULL(da.[Acesso_Bancos_de_Dados], 'Nenhum acesso explícito a bancos') AS [Acesso_Bancos_de_Dados],
    p.[Usuario de AD ou de Instancia],
    CASE 
        WHEN sl.password_hash IS NULL THEN 'Sem senha (Windows/externo)'
        WHEN SUBSTRING(sl.password_hash,1,1) = 0x02 THEN 'Formato v2 (SHA-512)'
        WHEN SUBSTRING(sl.password_hash,1,1) = 0x03 THEN 'Formato v3 (PBKDF2)'
        ELSE 'Formato desconhecido / legacy'
    END AS [Formato_Hash_Senha],
    sl.password_hash AS [Senha_Criptografada_Hash]
FROM
    ServerPrincipals AS p
LEFT JOIN
    ActiveSessions AS s ON p.Nome = s.login_name
LEFT JOIN
    ServerRoles AS r ON p.principal_id = r.member_principal_id
LEFT JOIN
    ServerPermissions AS pe ON p.principal_id = pe.grantee_principal_id
LEFT JOIN
    DatabaseAccess AS da ON p.sid = da.server_principal_sid
LEFT JOIN
    sys.sql_logins AS sl ON p.principal_id = sl.principal_id
ORDER BY
    p.Nome;


/*
========================================================================
   PARTE 3: Limpeza
   Remove a tabela temporária global.
========================================================================
*/
DROP TABLE #DBAcessos;

