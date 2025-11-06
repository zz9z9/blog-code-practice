package org.example;

import jakarta.persistence.*;
import lombok.*;
import java.time.LocalDateTime;

@Entity
@Getter @Setter
@NoArgsConstructor
@AllArgsConstructor
@Builder
public class MemberHistory {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long seq;

//    @Column(name = "member_id", nullable = false)
//    private Long memberId;

    @Column(name = "member_name", nullable = false)
    private String memberName;

    @Column(name = "action_type", nullable = false)
    private String actionType;

    @Column(name = "registered_at", nullable = false)
    private LocalDateTime registeredAt;

    @ManyToOne
    @JoinColumn(name = "member_id")
    private Member member;

}
