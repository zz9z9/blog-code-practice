package org.example;

import jakarta.persistence.EntityManager;
import jakarta.persistence.PersistenceContext;
import org.springframework.stereotype.Repository;
import org.springframework.transaction.annotation.Transactional;

import java.util.List;

@Repository
@Transactional
public class MemberRepository {

    @PersistenceContext
    private EntityManager em;

    public void save(Member member) {
        em.persist(member);
    }

//    public void save(Member member) {
//        em.persist(member);
//        em.flush(); // ID 생성 보장 (이후 member.getId() 사용 가능)
//
//        // 이력 저장
//        MemberHistory history = new MemberHistory();
//        history.setMemberId(member.getMemberId());
//        history.setMemberName(member.getMemberName());
//        history.setActionType("REGISTER");
//        history.setRegisteredAt(LocalDateTime.now());
//
//        em.persist(history);
//    }

    public Member find(Long id) {
        return em.find(Member.class, id);
    }

    public List<Member> findAll() {
        return em.createQuery("select m from Member m", Member.class)
                .getResultList();
    }

    public void delete(Long id) {
        Member member = em.find(Member.class, id);
        if (member != null) em.remove(member);
    }
}
