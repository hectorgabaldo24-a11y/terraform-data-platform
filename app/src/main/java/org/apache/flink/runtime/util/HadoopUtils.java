package org.apache.flink.runtime.util;

import org.apache.hadoop.conf.Configuration;

/**
 * Reemplazo minimo de {@code org.apache.flink.runtime.util.HadoopUtils} para usar Iceberg en
 * Managed Service for Apache Flink.
 *
 * <p>Iceberg ({@code FlinkCatalogFactory.clusterHadoopConf}) llama a HadoopUtils de Flink, que se
 * carga desde el classloader padre del runtime, donde no hay clases de Hadoop: falla con
 * {@code NoClassDefFoundError: org/apache/hadoop/conf/Configuration}. El shade del pom reubica esta
 * clase a {@code shadow.org.apache.flink.runtime.util.HadoopUtils} y reescribe las referencias de
 * Iceberg hacia ella, de modo que se carga desde el JAR de la aplicacion junto con Hadoop.
 *
 * <p>Devuelve una configuracion vacia: el catalogo usa GlueCatalog + S3FileIO (AWS SDK v2), que no
 * dependen de la configuracion de Hadoop. Mismo enfoque que el ejemplo oficial de AWS
 * (amazon-managed-service-for-apache-flink-examples, java/Iceberg/IcebergSQLSink).
 */
public class HadoopUtils {

    private HadoopUtils() {}

    public static Configuration getHadoopConfiguration(
            org.apache.flink.configuration.Configuration flinkConfiguration) {
        return new Configuration(false);
    }
}
