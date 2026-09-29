package com.zz9z9.blogcode.transaction.basic;

import org.springframework.stereotype.Service;
import org.springframework.transaction.annotation.Transactional;

@Service
public class TestServiceImpl implements TestService {

    @Override
    @Transactional
    public void foo() {
        System.out.println("foo");
    }



}
