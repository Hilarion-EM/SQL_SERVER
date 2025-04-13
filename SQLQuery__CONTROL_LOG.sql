use master;
go
-- ELIMINAR EL PROCEDIMIENTO SI EXISTE
DROP PROCEDURE IF EXISTS dbo.[SP_CONTROL_LOG];
GO

CREATE PROCEDURE [SP_CONTROL_LOG]

AS
BEGIN
    SET NOCOUNT ON;
    

DECLARE @DBName NVARCHAR(128);
DECLARE @LogFileName NVARCHAR(128);
DECLARE @LogSizeMB DECIMAL(18,2);
DECLARE @SQL NVARCHAR(1000);
DECLARE @TargetSizeMB INT = 100; -- Tamaño objetivo en MB después de reducción
DECLARE @MaxSizeMB INT = 1024;  -- Límite máximo para disparar la reducción (1 GB)

-- Tabla temporal para almacenar las bases de datos objetivo
DECLARE @Databases TABLE (DBName NVARCHAR(128));
INSERT INTO @Databases (DBName)
VALUES ('DB_TechNesis_Pruebas'), ('BD_REMISION'); -- Lista tus bases aquí

DECLARE db_cursor CURSOR FOR 
SELECT DBName FROM @Databases;

OPEN db_cursor;
FETCH NEXT FROM db_cursor INTO @DBName;

WHILE @@FETCH_STATUS = 0
BEGIN
    -- Obtener el nombre del archivo de log y su tamaño actual
    SELECT @LogFileName = name, @LogSizeMB = size * 8.0 / 1024.0
    FROM sys.master_files
    WHERE database_id = DB_ID(@DBName)
      AND type_desc = 'LOG';

    IF @LogSizeMB IS NOT NULL
    BEGIN
        PRINT 'Base de datos: ' + @DBName + ' - Tamaño actual del log: ' + CAST(@LogSizeMB AS NVARCHAR(20)) + ' MB';

        -- Si el log supera 1 GB, reducirlo
        IF @LogSizeMB > @MaxSizeMB
        BEGIN
            PRINT 'El log supera ' + CAST(@MaxSizeMB AS NVARCHAR(10)) + ' MB. Reduciendo a ' + CAST(@TargetSizeMB AS NVARCHAR(10)) + ' MB...';
            
            -- Construir y ejecutar comandos dinámicos para reducir el log
            SET @SQL = '
            USE ' + QUOTENAME(@DBName) + ';
            ALTER DATABASE ' + QUOTENAME(@DBName) + ' SET RECOVERY SIMPLE WITH NO_WAIT;
            DBCC SHRINKFILE (' + QUOTENAME(@LogFileName, '''') + ', ' + CAST(@TargetSizeMB AS NVARCHAR(10)) + ');
            ';
            -- Opcional: Volver a modo Completo si lo necesitas
            SET @SQL = @SQL + 'ALTER DATABASE ' + QUOTENAME(@DBName) + ' SET RECOVERY FULL WITH NO_WAIT;';

            BEGIN TRY
                EXEC sp_executesql @SQL;
                PRINT 'Log reducido exitosamente para ' + @DBName + '.';
            END TRY
            BEGIN CATCH
                PRINT 'Error al reducir el log de ' + @DBName + ': ' + ERROR_MESSAGE();
            END CATCH
        END
        ELSE
        BEGIN
            PRINT 'El tamaño del log está dentro del límite para ' + @DBName + '.';
        END

        -- Configurar tamaño inicial, crecimiento y establecer MAXSIZE = UNLIMITED
        SET @SQL = '
        USE ' + QUOTENAME(@DBName) + ';
        ALTER DATABASE ' + QUOTENAME(@DBName) + '
        MODIFY FILE (NAME = ' + QUOTENAME(@LogFileName, '''') + ', 
                     SIZE = ' + CAST(@TargetSizeMB AS NVARCHAR(10)) + 'MB, 
                     FILEGROWTH = 100MB, 
                     MAXSIZE = UNLIMITED);';
        BEGIN TRY
            -- Solo ejecutar si el tamaño actual es mayor al objetivo (evitar error 5039)
            IF @LogSizeMB > @TargetSizeMB
            BEGIN
                EXEC sp_executesql @SQL;
                PRINT 'Tamaño inicial, crecimiento y MAXSIZE = UNLIMITED configurados para ' + @DBName + '.';
            END
            ELSE
            BEGIN
                -- Si el log ya está en o por debajo del objetivo, solo ajustar MAXSIZE y FILEGROWTH
                SET @SQL = '
                ALTER DATABASE ' + QUOTENAME(@DBName) + '
                MODIFY FILE (NAME = ' + QUOTENAME(@LogFileName, '''') + ', 
                             FILEGROWTH = 100MB, 
                             MAXSIZE = UNLIMITED);';
                EXEC sp_executesql @SQL;
                PRINT 'Crecimiento y MAXSIZE = UNLIMITED configurados para ' + @DBName + '.';
            END
        END TRY
        BEGIN CATCH
            PRINT 'Error al configurar propiedades del log para ' + @DBName + ': ' + ERROR_MESSAGE();
        END CATCH
    END

    FETCH NEXT FROM db_cursor INTO @DBName;
END

CLOSE db_cursor;
DEALLOCATE db_cursor;

END;
