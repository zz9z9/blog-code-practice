package com.zz9z9.blogcode.springbatch.in.action.config.initializer;

import org.springframework.beans.factory.annotation.Qualifier;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.io.ClassPathResource;
import org.springframework.jdbc.datasource.init.DataSourceInitializer;
import org.springframework.jdbc.datasource.init.ResourceDatabasePopulator;

import javax.sql.DataSource;

@Configuration
public class MainSchemaInitializer {

    @Bean
    public DataSourceInitializer mainDataSourceInitializer(@Qualifier("mainDataSource") DataSource mainDataSource) {

        ResourceDatabasePopulator populator = new ResourceDatabasePopulator();
        populator.addScript(new ClassPathResource("schema-all.sql"));

        DataSourceInitializer initializer = new DataSourceInitializer();
        initializer.setDataSource(mainDataSource);
        initializer.setDatabasePopulator(populator);

        return initializer;
    }
}
