---Query basica para criação de usuarios.
-- Sei que as vezes bate a duvida no JR, PL e SR . Com a correria acabamos esquecendo algumas coisas basicas
-- Segue aqui minha query que sempre utilizo , mas lembrem-se , pratiquem para decorar. 

--Criando usuario AD
use master
go
--usuario AD
CREATE LOGIN [user/group] FROM WINDOWS;
--User Local
--CREATE LOGIN [user/group] WITH PASSWORD = 'SenhaForte123!';
go

use BASEXXXX
go
CREATE USER [user/group] FOR LOGIN [user/group];
go


--Add Role
EXEC sp_addrolemember 'db_datareader', [user/group];

--| Role                | Descrição                                                                     |
--| ------------------- | ----------------------------------------------------------------------------- |
--| `db_owner`          | Acesso total à base de dados, inclusive gerenciamento de segurança e objetos. |
--| `db_accessadmin`    | Pode adicionar ou remover usuários do banco.                                  |
--| `db_securityadmin`  | Pode gerenciar permissões e roles no banco.                                   |
--| `db_ddladmin`       | Pode criar, alterar ou remover objetos do banco (tabelas, views, procs etc).  |
--| `db_backupoperator` | Pode realizar backups da base de dados.                                       |
--| `db_datareader`     | Pode executar SELECT em todas as tabelas e views.                             |
--| `db_datawriter`     | Pode executar INSERT, UPDATE e DELETE em todas as tabelas e views.            |
--| `db_denydatareader` | **Nega** permissão de leitura (SELECT) em todas as tabelas/views.             |
--| `db_denydatawriter` | **Nega** permissão de escrita (INSERT, UPDATE, DELETE).                       |
---------------------------------------------------------------------------------------------------------


-- Add Role Servidor
ALTER SERVER ROLE sysadmin ADD MEMBER [user/group];

-- LISTA DE ROLES SQL SERVER
--| Nome da Role      | Descrição                                         |
--| ----------------- | ------------------------------------------------- |
--| **sysadmin**      | Controle total sobre o servidor                   |
--| **serveradmin**   | Pode alterar configurações do servidor            |
--| **securityadmin** | Gerencia logins e permissões de nível de servidor |
--| **setupadmin**    | Pode configurar links e configurar o servidor     |
--| **processadmin**  | Pode gerenciar processos (KILL)                   |
--| **diskadmin**     | Gerencia arquivos físicos                         |
--| **dbcreator**     | Pode criar, alterar e deletar bancos de dados     |
--| **bulkadmin**     | Pode executar operações de bulk insert            |
---------------------------------------------------------------------------

--PARA DELETAR O user/group de todas as bases

-- Gera os comandos para remover o USER nas bases:
DECLARE @Login NVARCHAR(128) = 'usuario/group';
DECLARE @SQL NVARCHAR(MAX) = '';

SELECT @SQL = @SQL + '
USE [' + name + '];
IF EXISTS (SELECT 1 FROM sys.database_principals WHERE name = ''' + @Login + ''')
BEGIN
    DROP USER [' + @Login + '];
END;
'
FROM sys.databases
WHERE state = 0 AND name NOT IN ('tempdb'); -- exclui tempdb

PRINT @SQL;
-- Depois de revisar, execute:
--EXEC sp_executesql @SQL;
