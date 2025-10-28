/*
********************************************************
Autor :  Fabio Henrique da Silva
linkedin: https://www.linkedin.com/in/fabio-henriques/
Assunto: Scrip para auditoria de Acessos , usuarios de instancias VS Usuarios de AD.
  Conseguimos ter acesso aos dados como (Nome, UltimoAcesso 'Aproximadamente', tipo de roles, permissões , tipo do usuarios, formato hash e hash da senha . 
Blog que usei para referencia: https://dirceuresende.com/blog/sql-server-como-saber-a-data-do-ultimo-login-de-um-usuario/
*/

-- 1. Coleta todos os logins de usuário (SQL, Windows e Grupos)
WITH ServerPrincipals AS (
    SELECT
        principal_id,
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

-- 5. Agrega informações da hash senha.
Cripto as (
SELECT name,
       CASE 
         WHEN password_hash IS NULL THEN 'Sem senha (Windows/externo)'
         WHEN SUBSTRING(password_hash,1,1) = 0x02 THEN 'Formato v2 (SHA-512 style - SQL Server <= 2022)'
         WHEN SUBSTRING(password_hash,1,1) = 0x03 THEN 'Formato v3 (PBKDF2 / RFC2898 - SQL 2025+)'
         ELSE 'Formato desconhecido / legacy'
       END AS hash_formato,
       DATALENGTH(password_hash) AS hash_bytes
FROM sys.sql_logins
)


-- 6. Junta todas as informações (Final)
SELECT
    p.Nome,
    CASE
        WHEN p.type = 'S' THEN CONVERT(DATETIME, LOGINPROPERTY(p.Nome, 'LastLoginTime'))
        ELSE s.UltimoAcessoSessaoAtiva -- Não substitui o audit, eu vi no blog do Dirceu. Sendo assim melhor implementar.
    END AS [Ultimo Acesso (Aproximado)],
    ISNULL(r.[Tipo de Role], 'public') AS [Tipo de Role],
    ISNULL(pe.Permissoes, 'Nenhuma permissão explícita no servidor') AS Permissoes,
    p.[Usuario de AD ou de Instancia],
     CASE 
         WHEN password_hash IS NULL THEN 'Sem senha (Windows/externo)'
         WHEN SUBSTRING(password_hash,1,1) = 0x02 THEN 'Formato v2 (SHA-512 style - SQL Server <= 2022)'
         WHEN SUBSTRING(password_hash,1,1) = 0x03 THEN 'Formato v3 (PBKDF2 / RFC2898 - SQL 2025+)'
         ELSE 'Formato desconhecido / legacy'
       END AS hash_formato,
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
    Cripto AS cp ON p.nome = cp.name
LEFT JOIN
    sys.sql_logins AS sl ON p.principal_id = sl.principal_id
ORDER BY
    p.Nome;
