package org.example;

import jakarta.persistence.CascadeType;
import jakarta.persistence.Entity;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.Id;
import jakarta.persistence.OneToMany;
import lombok.Getter;

import java.time.LocalDateTime;
import java.util.ArrayList;
import java.util.List;

@Entity
@Getter
public class Member {
    @Id
    @GeneratedValue
    private Long memberId;

    private String memberName;

    @OneToMany(mappedBy = "member", cascade = CascadeType.PERSIST)
    private List<MemberHistory> histories = new ArrayList<>();

    public void addHistory() {
        MemberHistory history = new MemberHistory();
//        history.setMemberId(memberId);
        history.setMemberName(memberName);
        history.setActionType("REGISTER");
        history.setRegisteredAt(LocalDateTime.now());

        histories.add(history);
        history.setMember(this);
    }

}
