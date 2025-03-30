USE [DB_TechNesis_Pruebas]
GO

DECLARE @RutaArchivo NVARCHAR(500)
DECLARE @NombreArchivo NVARCHAR(255)
DECLARE @SQL NVARCHAR(1000)

-- Eliminar tabla temporal si existe
IF OBJECT_ID('tempdb..#ArchivosCSV') IS NOT NULL
    DROP TABLE #ArchivosCSV

-- Crear tabla temporal para almacenar nombres de archivos
CREATE TABLE #ArchivosCSV (
    NombreArchivo NVARCHAR(255),
    SubDirectorio NVARCHAR(255),
    EsArchivo BIT
)

-- Obtener lista de archivos usando xp_dirtree
INSERT INTO #ArchivosCSV (NombreArchivo, SubDirectorio, EsArchivo)
EXEC xp_dirtree 'C:\Users\HEM\Downloads\Descargas\CSV', 1, 1 

-- Filtrar solo archivos CSV
DELETE FROM #ArchivosCSV 
WHERE NombreArchivo NOT LIKE '%.csv' 
   OR EsArchivo = 0

-- Declarar cursor para iterar sobre los archivos
DECLARE cursor_archivos CURSOR FOR 
SELECT NombreArchivo 
FROM #ArchivosCSV

OPEN cursor_archivos
FETCH NEXT FROM cursor_archivos INTO @NombreArchivo

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @RutaArchivo = 'C:\Users\HEM\Downloads\Descargas\CSV\' + @NombreArchivo
    
    PRINT 'Procesando archivo: ' + @RutaArchivo

    -- Construir la instrucción BULK INSERT dinámicamente
    SET @SQL = '
    BULK INSERT dbo.T_ATENCIONES_SIS
    FROM ''' + @RutaArchivo + '''
    WITH (
        FIELDTERMINATOR = '','',
        ROWTERMINATOR = ''\n'',
        FIRSTROW = 2,    -- Saltar encabezado si existe
        DATAFILETYPE = ''char'',
        CODEPAGE = ''65001'',  -- UTF-8
        ERRORFILE = ''C:\Users\HEM\Downloads\Descargas\Errores_' + REPLACE(@NombreArchivo, '.csv', '') + '.log'',
        CHECK_CONSTRAINTS,
        TABLOCK
    )'

    BEGIN TRY
        EXEC sp_executesql @SQL
        PRINT 'Archivo procesado exitosamente: ' + @NombreArchivo
    END TRY
    BEGIN CATCH
        PRINT 'Error al procesar archivo: ' + @NombreArchivo + ' - ' + ERROR_MESSAGE()
    END CATCH

    FETCH NEXT FROM cursor_archivos INTO @NombreArchivo
END

-- Limpiar
CLOSE cursor_archivos
DEALLOCATE cursor_archivos
DROP TABLE #ArchivosCSV