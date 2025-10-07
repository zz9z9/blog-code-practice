package com.zz9z9.blogcode.springbatch.in.action;

import lombok.AllArgsConstructor;
import lombok.Data;

@Data
@AllArgsConstructor
class OrderProduct {

    private int seq;
    private int orderNo;
    private int productId;
    private int quantity;

}