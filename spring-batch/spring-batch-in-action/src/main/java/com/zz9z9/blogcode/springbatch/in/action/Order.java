package com.zz9z9.blogcode.springbatch.in.action;

import lombok.AllArgsConstructor;
import lombok.Data;

import java.time.LocalDate;

@Data
@AllArgsConstructor
class Order {

    private int orderNo;
    private int userId;
    private LocalDate orderDate;
    private int orderAmount;

}