"""Explicit source-first review amendments. Never changes formal source text."""
DISPLAY = {
    ('transaction',('s001','s002','s003')):'交易／买卖（生意限具体交易语境）',
    ('annual',('s004',)):'一年生植物（生命周期在一年内完成）',
    ('bias',('s002',)):'偏差（数据或方法的系统性偏向）',
    ('percentage',('s001',)):'比率（整体份额，常按百分数表示）',
    ('chart',('s003',)):'记录变化（以图表等方式）',
    ('corporation',('s002',)):'法人团体（依法作为独立主体）',
    ('classical',('s002',)):'传统的（长期确立的形式或风格）',
    ('core',('s002',)):'果核（苹果、梨等的中央含籽部分）',
    ('fundamental',('s003',)):'基本原则（常用复数 fundamentals）',
    ('profitable',('s002',)):'有益的；有收获的（不限于经济利润）',
    ('management',('s001',)):'指导（组织管理事务的语境）',
    ('management',('s002',)):'指挥（组织管理活动的语境）',
    ('locate',('s002',)):'坐落于（常用 be located in 等结构）',
    ('machinery',('s001','s002','s003')):'机械设备（集合称呼，通常不可数）',
    ('nuclear',('s001',)):'原子的（限核能、原子核相关语境）',
    ('appropriate',('s003',)):'挪用；擅自拿来己用',
    ('primary',('s002',)):'初级的（如儿童初级教育）',
    ('primary',('s003',)):'最初的（首先发生的）',
    ('permanent',('s002',)):'长期的（持续稳定、非临时的语境）',
    ('rigid',('s002',)):'严格的（缺乏灵活性、不可妥协的语境）',
    ('private',('s002',)):'私有的（非公共、专属于个人或群体）',
    ('appreciate',('s003',)):'理解（充分意识到情况或价值）',
    ('imply',('s001','s002')):'意味着（由此可推知）',
    ('regulate',('s002','s003')):'管理／控制（按规则约束或使合规）',
    ('suppress',('s003',)):'禁止（限阻止表达、流通或运作等语境）',
    ('critical',('s001',)):'批评的（指出不足）',
}

# Every initial reference gap is explicitly resolved by a retrieved publisher
# observation, not by guessing that any same-POS WordNet item is suitable.
REFERENCE_FIX = {('bias','s002'):'bias', ('corporation','s002'):'corporation',
    ('faculty','s003'):'faculty', ('profitable','s002'):'profitable',
    ('fundamental','s003'):'fundamental', ('impact','s004'):'impact',
    ('plastic','s002'):'plastic', ('suppress','s003'):'suppress',
    ('prior','s002'):'prior', ('privilege','s002'):'privilege',
    ('appropriate','s003'):'appropriate', ('property','s001'):'property'}
