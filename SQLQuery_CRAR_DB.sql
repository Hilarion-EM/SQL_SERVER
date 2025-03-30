USE master;
GO

-- Declarar variables para centralizar el nombre y la ruta
DECLARE @DatabaseName NVARCHAR(50) = 'DB_TechNesis_Pruebas'; -- Nombre de la base de datos
DECLARE @BasePath NVARCHAR(255) = 'C:\Program Files\Microsoft SQL Server\MSSQL16.MSSQLSERVER\MSSQL\DATA\';      -- Ruta base (termina con '\')
DECLARE @SqlCommand NVARCHAR(MAX);                    -- Para construir el comando dinámico

-- Construir el comando CREATE DATABASE usando las variables
SET @SqlCommand = '
CREATE DATABASE ' + QUOTENAME(@DatabaseName) + '
ON 
PRIMARY
(
    NAME = ''' + @DatabaseName + '_Primary'',
    FILENAME = ''' + @BasePath + @DatabaseName + '.mdf'',
    SIZE = 100MB,
    MAXSIZE = UNLIMITED,
    FILEGROWTH = 100MB
),
FILEGROUP Secundario
(
    NAME = ''' + @DatabaseName + '_Secundario'',
    FILENAME = ''' + @BasePath + @DatabaseName + '_Secundario.ndf'',
    SIZE = 100MB,
    MAXSIZE = UNLIMITED,
    FILEGROWTH = 100MB
)
LOG ON
(
    NAME = ''' + @DatabaseName + '_Log'',
    FILENAME = ''' + @BasePath + @DatabaseName + '_Log.ldf'',
    SIZE = 100MB,
    MAXSIZE = UNLIMITED,
    FILEGROWTH = 100MB
);
';

-- Ejecutar el comando
EXEC sp_executesql @SqlCommand;

-- Verificar la creación
SELECT name, physical_name, size, max_size, growth
FROM sys.master_files
WHERE database_id = DB_ID(@DatabaseName);
GO


