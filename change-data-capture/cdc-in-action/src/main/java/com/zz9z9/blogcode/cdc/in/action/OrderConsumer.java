package com.zz9z9.blogcode.cdc.in.action;

import org.springframework.kafka.annotation.KafkaListener;
import org.springframework.stereotype.Component;

@Component
public class OrderConsumer {

    @KafkaListener(topics = "mysql-cdc.ordersdb.orders", groupId = "cdc-group")
    public void consume(String message) {
        System.out.println("CDC Event: " + message);
    }
}
