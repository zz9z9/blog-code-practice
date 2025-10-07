package com.zz9z9.blogcode.springbatch.in.action;

import lombok.RequiredArgsConstructor;
import net.datafaker.Faker;
import org.springframework.batch.core.Job;
import org.springframework.batch.core.Step;
import org.springframework.batch.core.job.builder.FlowBuilder;
import org.springframework.batch.core.job.builder.JobBuilder;
import org.springframework.batch.core.job.flow.Flow;
import org.springframework.batch.core.repository.JobRepository;
import org.springframework.batch.core.step.builder.StepBuilder;
import org.springframework.batch.item.database.JdbcBatchItemWriter;
import org.springframework.batch.item.database.builder.JdbcBatchItemWriterBuilder;
import org.springframework.batch.item.support.IteratorItemReader;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.scheduling.concurrent.ThreadPoolTaskExecutor;
import org.springframework.transaction.PlatformTransactionManager;

import javax.sql.DataSource;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.List;
import java.util.Random;

@Configuration
@RequiredArgsConstructor
public class DataImportJobConfiguration {

    private final JobRepository jobRepository;
    private final PlatformTransactionManager transactionManager;
    private final DataSource mainDataSource;

    private final Faker faker = new Faker();
    private final Random random = new Random();

    @Bean
    public JdbcBatchItemWriter<User> userWriter() {
        return new JdbcBatchItemWriterBuilder<User>()
                .dataSource(mainDataSource)
                .sql("INSERT INTO users (name, age) VALUES (:name, :age)")
                .beanMapped()
                .build();
    }

    @Bean
    public Step userStep(JdbcBatchItemWriter<User> userWriter) {
        return new StepBuilder("userStep", jobRepository)
                .<User, User>chunk(1000, transactionManager)
                .reader(new IteratorItemReader<>(generateUsers()))
                .writer(userWriter)
                .build();
    }

    @Bean
    public JdbcBatchItemWriter<Order> orderWriter() {
       return new JdbcBatchItemWriterBuilder<Order>()
                .dataSource(mainDataSource)
                .sql("INSERT INTO orders (order_no, user_id, order_date, order_amount) " +
                        "VALUES (:orderNo, :userId, :orderDate, :orderAmount)")
                .beanMapped()
                .build();
    }

    @Bean
    public Step orderStep(JdbcBatchItemWriter<Order> orderWriter) {
        return new StepBuilder("orderStep", jobRepository)
                .<Order, Order>chunk(10000, transactionManager)
                .reader(new IteratorItemReader<>(generateOrders()))
                .writer(orderWriter)
                .build();
    }

    @Bean
    public JdbcBatchItemWriter<OrderProduct> orderProductWriter() {
        return new JdbcBatchItemWriterBuilder<OrderProduct>()
                .dataSource(mainDataSource)
                .sql("INSERT INTO order_products (order_no, product_id, quantity) " +
                        "VALUES (:orderNo, :productId, :quantity)")
                .beanMapped()
                .build();
    }


    @Bean
    public Step orderProductStep(JdbcBatchItemWriter<OrderProduct> orderProductWriter) {
        return new StepBuilder("orderProductStep", jobRepository)
                .<OrderProduct, OrderProduct>chunk(10000, transactionManager)
                .reader(new IteratorItemReader<>(generateOrderProducts()))
                .writer(orderProductWriter)
                .build();
    }

    @Bean
    public Job dataImportJob(Step userStep, Step orderStep,  Step orderProductStep) {
        Flow userFlow = new FlowBuilder<Flow>("userFlow").start(userStep).build();
        Flow orderFlow = new FlowBuilder<Flow>("orderFlow").start(orderStep).build();
        Flow productFlow = new FlowBuilder<Flow>("productFlow").start(orderProductStep).build();

        return new JobBuilder("dataImportJob", jobRepository)
                .start(userFlow)
                .split(batchTaskExecutor())
                .add(orderFlow, productFlow)
                .end()
                .build();
    }

    @Bean
    public ThreadPoolTaskExecutor batchTaskExecutor() {
        ThreadPoolTaskExecutor executor = new ThreadPoolTaskExecutor();
        executor.setCorePoolSize(10);    // 기본 스레드 수
        executor.setMaxPoolSize(10);     // 최대 스레드 수
        executor.setQueueCapacity(100); // 큐 용량
        executor.setThreadNamePrefix("batch-thread-");
        executor.initialize();
        return executor;
    }

    // --- 데이터 생성부 ---
    private List<User> generateUsers() {
        List<User> list = new ArrayList<>(10_000);
        for (int i = 1; i <= 10_000; i++) {
            list.add(new User(i, faker.name().fullName(), 18 + random.nextInt(50)));
        }
        return list;
    }

    private List<Order> generateOrders() {
        List<Order> list = new ArrayList<>(1_000_000);
        for (int i = 1; i <= 1_000_000; i++) {
            list.add(new Order(
                    i,
                    1 + random.nextInt(10_000),
                    LocalDate.now().minusDays(random.nextInt(365)),
                    random.nextInt(50000) + 1000
            ));
        }
        return list;
    }

    private List<OrderProduct> generateOrderProducts() {
        List<OrderProduct> list = new ArrayList<>(10_000_000);
        for (int i = 1; i <= 10_000_000; i++) {
            list.add(new OrderProduct(
                    i,
                    1 + random.nextInt(1_000_000),
                    random.nextInt(10000),
                    1 + random.nextInt(5)
            ));
        }
        return list;
    }

}
