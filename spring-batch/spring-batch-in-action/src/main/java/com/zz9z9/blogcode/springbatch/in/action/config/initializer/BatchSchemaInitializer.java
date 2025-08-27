package com.zz9z9.blogcode.springbatch.in.action.config.initializer;

import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.io.ClassPathResource;
import org.springframework.jdbc.datasource.init.DataSourceInitializer;
import org.springframework.jdbc.datasource.init.ResourceDatabasePopulator;

import javax.sql.DataSource;

//@Configuration
//public class BatchSchemaInitializer {
//
//    @Bean
//    public DataSourceInitializer batchDataSourceInitializer(
//            @Qualifier("batchDataSource") DataSource batchDataSource) {
//
//        ResourceDatabasePopulator populator = new ResourceDatabasePopulator();
//        populator.addScript(new ClassPathResource("org/springframework/batch/core/schema-mysql.sql"));
//
//        DataSourceInitializer initializer = new DataSourceInitializer();
//        initializer.setDataSource(batchDataSource);
//        initializer.setDatabasePopulator(populator);
//
//        return initializer;
//    }
//
//}