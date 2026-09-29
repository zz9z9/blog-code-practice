package com.zz9z9.blogcode.transaction.basic;

import org.springframework.boot.SpringApplication;
import org.springframework.boot.autoconfigure.SpringBootApplication;
import org.springframework.cglib.core.DebuggingClassWriter;
import org.springframework.cglib.proxy.Enhancer;

@SpringBootApplication
public class DemoApplication {

    public static void main(String[] args) {
//        System.setProperty(DebuggingClassWriter.DEBUG_LOCATION_PROPERTY, "/tmp/cglib");
        SpringApplication.run(DemoApplication.class, args);
    }

//    public static void main(String[] args) {
//        Enhancer enhancer = new Enhancer();
//        enhancer.setSuperclass(TempService.class); // 원본 클래스 지정
//        enhancer.setCallback(new TempInterceptor()); // 인터셉터 지정
//
//        // 프록시 인스턴스 생성
//        TempService proxy = (TempService) enhancer.create();
//
//        // 프록시 메서드 호출 (intercept → invokeSuper → 원본 호출)
//        proxy.hello("CGLIB");
//    }

}
