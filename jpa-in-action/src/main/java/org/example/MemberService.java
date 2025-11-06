package org.example;

import lombok.RequiredArgsConstructor;
import org.springframework.stereotype.Service;

import java.util.List;

@Service
@RequiredArgsConstructor
public class MemberService {

    private final MemberRepository memberRepository;

    public void join(Member member) {
        member.addHistory();
        memberRepository.save(member);
    }

    public List<Member> list() {
        return memberRepository.findAll();
    }

}
