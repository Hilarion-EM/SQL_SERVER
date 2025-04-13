USE [DB_TechNesis_Pruebas]
GO

DECLARE @RutaArchivo NVARCHAR(500)
DECLARE @NombreArchivo NVARCHAR(255)
DECLARE @SQL NVARCHAR(4000)
DECLARE @Año INT
DECLARE @SumaCSV BIGINT
DECLARE @SumaSQL BIGINT

-- Eliminar tablas temporales si existen
IF OBJECT_ID('tempdb..#ArchivosCSV') IS NOT NULL
    DROP TABLE #ArchivosCSV

IF OBJECT_ID('tempdb..#DatosCSVConsolidados') IS NOT NULL
    DROP TABLE #DatosCSVConsolidados

IF OBJECT_ID('tempdb..#SumaPorAñoCSV') IS NOT NULL
    DROP TABLE #SumaPorAñoCSV

-- Crear tabla temporal para almacenar nombres de archivos
CREATE TABLE #ArchivosCSV (
    NombreArchivo NVARCHAR(255),
    SubDirectorio NVARCHAR(255),
    EsArchivo BIT
)

-- Crear tabla temporal para consolidar todos los datos de los CSV
CREATE TABLE #DatosCSVConsolidados (
AÑO VARCHAR(10),
MES VARCHAR(5),
REGION VARCHAR(100),
PROVINCIA VARCHAR(100),
UBIGEO_DISTRITO VARCHAR(15),
DISTRITO VARCHAR(100),
COD_UNIDAD_EJECUTORA VARCHAR(10),
DESC_UNIDAD_EJECUTORA VARCHAR(100),
COD_IPRESS VARCHAR(20),
IPRESS VARCHAR(100),
NIVEL_EESS VARCHAR(10),
PLAN_SEGURO VARCHAR(40),
COD_SERVICIO VARCHAR(10),
DESC_SERVICIO VARCHAR(100),
SEXO VARCHAR(25),
GRUPO_EDAD VARCHAR(25),
ATENCIONES INT
)

-- Crear tabla temporal para la suma de ATENCIONES por año desde todos los CSV
CREATE TABLE #SumaPorAñoCSV (
    AÑO INT,
    SumaAtenciones BIGINT
)

-- Obtener lista de archivos usando xp_dirtree
INSERT INTO #ArchivosCSV (NombreArchivo, SubDirectorio, EsArchivo)
EXEC xp_dirtree 'C:\Users\HEM\Downloads\Descargas\CSV', 1, 1 

-- Filtrar solo archivos CSV
DELETE FROM #ArchivosCSV 
WHERE NombreArchivo NOT LIKE '%.csv' 
   OR EsArchivo = 0

-- Paso 1: Consolidar todos los CSV en una tabla temporal
DECLARE cursor_archivos CURSOR FOR 
SELECT NombreArchivo 
FROM #ArchivosCSV

OPEN cursor_archivos
FETCH NEXT FROM cursor_archivos INTO @NombreArchivo

WHILE @@FETCH_STATUS = 0
BEGIN
    SET @RutaArchivo = 'C:\Users\HEM\Downloads\Descargas\CSV\' + @NombreArchivo
    
    PRINT 'Cargando archivo a consolidado: ' + @RutaArchivo

    -- Cargar datos del CSV a la tabla consolidada
    SET @SQL = '
    BULK INSERT #DatosCSVConsolidados
    FROM ''' + @RutaArchivo + '''
    WITH (
        FIELDTERMINATOR = '','',
        ROWTERMINATOR = ''\n'',
        FIRSTROW = 2,
        DATAFILETYPE = ''char'',
        CODEPAGE = ''65001'',
        ERRORFILE = ''C:\Users\HEM\Downloads\Descargas\Errores_' + REPLACE(@NombreArchivo, '.csv', '') + '.log'',
        TABLOCK
    )'

    BEGIN TRY
        EXEC sp_executesql @SQL
        PRINT 'Datos cargados desde: ' + @NombreArchivo
    END TRY
    BEGIN CATCH
        PRINT 'Error al cargar archivo: ' + @NombreArchivo + ' - ' + ERROR_MESSAGE()
    END CATCH

    FETCH NEXT FROM cursor_archivos INTO @NombreArchivo
END

CLOSE cursor_archivos
DEALLOCATE cursor_archivos

-- Paso 2: Calcular suma de ATENCIONES por AÑO en los CSV consolidados
INSERT INTO #SumaPorAñoCSV (AÑO, SumaAtenciones)
SELECT AÑO, SUM(ATENCIONES)
FROM #DatosCSVConsolidados
GROUP BY AÑO

-- Paso 3: Procesar cada año consolidado
DECLARE cursor_años CURSOR FOR 
SELECT AÑO, SumaAtenciones 
FROM #SumaPorAñoCSV

OPEN cursor_años
FETCH NEXT FROM cursor_años INTO @Año, @SumaCSV

WHILE @@FETCH_STATUS = 0
BEGIN
    -- Obtener suma de ATENCIONES para el año en SQL
    SELECT @SumaSQL = SUM(ATENCIONES)
    FROM dbo.T_ATENCIONES_SIS
    WHERE AÑO = @Año

    IF @SumaSQL IS NULL -- Año no existe en SQL
    BEGIN
        PRINT 'Año ' + CAST(@Año AS NVARCHAR(4)) + ' no existe en SQL. Insertando todos los registros.'
        INSERT INTO dbo.T_ATENCIONES_SIS (
            AÑO, MES, REGION, PROVINCIA, UBIGEO_DISTRITO, DISTRITO, 
            COD_UNIDAD_EJECUTORA, DESC_UNIDAD_EJECUTORA, COD_IPRESS, IPRESS, 
            NIVEL_EESS, PLAN_SEGURO, COD_SERVICIO, DESC_SERVICIO, SEXO, 
            GRUPO_EDAD, ATENCIONES
        )
        SELECT 
            AÑO, MES, REGION, PROVINCIA, UBIGEO_DISTRITO, DISTRITO, 
            COD_UNIDAD_EJECUTORA, DESC_UNIDAD_EJECUTORA, COD_IPRESS, IPRESS, 
            NIVEL_EESS, PLAN_SEGURO, COD_SERVICIO, DESC_SERVICIO, SEXO, 
            GRUPO_EDAD, ATENCIONES
        FROM #DatosCSVConsolidados
        WHERE AÑO = @Año
        PRINT 'Registros insertados para el año ' + CAST(@Año AS NVARCHAR(4)) + ': ' + CAST(@@ROWCOUNT AS NVARCHAR(10))
    END
    ELSE IF @SumaSQL = @SumaCSV -- Sumas coinciden, omitir carga
    BEGIN
        PRINT 'Año ' + CAST(@Año AS NVARCHAR(4)) + ' ya existe y las sumas coinciden (SQL: ' + CAST(@SumaSQL AS NVARCHAR(20)) + ', CSV: ' + CAST(@SumaCSV AS NVARCHAR(20)) + '). Omitiendo carga.'
    END
    ELSE -- Sumas difieren, comparar registro por registro
    BEGIN
        PRINT 'Año ' + CAST(@Año AS NVARCHAR(4)) + ' existe pero sumas difieren (SQL: ' + CAST(@SumaSQL AS NVARCHAR(20)) + ', CSV: ' + CAST(@SumaCSV AS NVARCHAR(20)) + '). Comparando registros.'
        
        INSERT INTO dbo.T_ATENCIONES_SIS (
            AÑO, MES, REGION, PROVINCIA, UBIGEO_DISTRITO, DISTRITO, 
            COD_UNIDAD_EJECUTORA, DESC_UNIDAD_EJECUTORA, COD_IPRESS, IPRESS, 
            NIVEL_EESS, PLAN_SEGURO, COD_SERVICIO, DESC_SERVICIO, SEXO, 
            GRUPO_EDAD, ATENCIONES
        )
        SELECT 
            d.AÑO, d.MES, d.REGION, d.PROVINCIA, d.UBIGEO_DISTRITO, d.DISTRITO, 
            d.COD_UNIDAD_EJECUTORA, d.DESC_UNIDAD_EJECUTORA, d.COD_IPRESS, d.IPRESS, 
            d.NIVEL_EESS, d.PLAN_SEGURO, d.COD_SERVICIO, d.DESC_SERVICIO, d.SEXO, 
            d.GRUPO_EDAD, d.ATENCIONES
        FROM #DatosCSVConsolidados d
        LEFT JOIN dbo.T_ATENCIONES_SIS t
            ON t.AÑO = d.AÑO
            AND t.MES = d.MES
            AND t.UBIGEO_DISTRITO = d.UBIGEO_DISTRITO
            AND t.COD_IPRESS = d.COD_IPRESS
            AND t.COD_SERVICIO = d.COD_SERVICIO
            AND t.SEXO = d.SEXO
            AND t.GRUPO_EDAD = d.GRUPO_EDAD
        WHERE t.AÑO IS NULL -- Solo insertar registros nuevos
          AND d.AÑO = @Año

        PRINT 'Registros nuevos insertados para el año ' + CAST(@Año AS NVARCHAR(4)) + ': ' + CAST(@@ROWCOUNT AS NVARCHAR(10))
    END

    FETCH NEXT FROM cursor_años INTO @Año, @SumaCSV
END

CLOSE cursor_años
DEALLOCATE cursor_años

-- Limpiar
DROP TABLE #ArchivosCSV
DROP TABLE #DatosCSVConsolidados
DROP TABLE #SumaPorAñoCSV