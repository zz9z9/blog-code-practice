//package com.zz9z9.blogcode.transaction.basic;
//
//import lombok.RequiredArgsConstructor;
//import org.springframework.web.bind.annotation.*;
//
//import java.util.List;
//import java.util.concurrent.CompletableFuture;
//
//@RestController
//@RequestMapping("/users")
//@RequiredArgsConstructor
//public class UserController {
//
//    private final UserService userService;
//    private final TestService testService;
//
//    @GetMapping
//    public List<User> getUsers() {
//        return userService.getAllUsers();
//    }
//
//    @PostMapping
//    public User createUser(@RequestBody User user) {
//        CompletableFuture.runAsync()
//        return userService.create(user);
//    }
//
//}