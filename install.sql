-- ============================================================
--  AX_QuestCreator | install.sql
-- ============================================================

CREATE TABLE IF NOT EXISTS `ax_quests` (
  `id`               INT(11)      NOT NULL AUTO_INCREMENT,
  `name`             VARCHAR(100) NOT NULL,
  `description`      TEXT         NOT NULL,
  `type`             ENUM('DELIVERY','TERRITORY') NOT NULL,
  `difficulty`       ENUM('easy','medium','hard','extreme') NOT NULL DEFAULT 'easy',
  `faction_id`       VARCHAR(50)  DEFAULT NULL COMMENT 'NULL = disponible para todas las facciones',
  `objective_data`   JSON         NOT NULL COMMENT 'Datos específicos según tipo de misión',
  `rewards`          JSON         NOT NULL COMMENT '{"money":5000,"items":[{"name":"item","amount":1}]}',
  `is_active`        TINYINT(1)   NOT NULL DEFAULT 1,
  `created_by`       VARCHAR(50)  NOT NULL,
  `created_at`       TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `updated_at`       TIMESTAMP    NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
  PRIMARY KEY (`id`),
  KEY `idx_faction` (`faction_id`),
  KEY `idx_active`  (`is_active`)
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ─────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS `ax_quest_instances` (
  `id`           INT(11)     NOT NULL AUTO_INCREMENT,
  `quest_id`     INT(11)     NOT NULL,
  `faction_id`   VARCHAR(50) NOT NULL,
  `accepted_by`  VARCHAR(50) NOT NULL,
  `status`       ENUM('active','completed','failed') NOT NULL DEFAULT 'active',
  `progress`     JSON        NOT NULL DEFAULT ('{}'),
  `started_at`   TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `completed_at` TIMESTAMP   NULL DEFAULT NULL,
  PRIMARY KEY (`id`),
  KEY `idx_quest`   (`quest_id`),
  KEY `idx_faction` (`faction_id`),
  KEY `idx_status`  (`status`),
  CONSTRAINT `fk_instance_quest` FOREIGN KEY (`quest_id`) REFERENCES `ax_quests` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ─────────────────────────────────────────────────────────────

CREATE TABLE IF NOT EXISTS `ax_quest_cooldowns` (
  `faction_id`     VARCHAR(50) NOT NULL,
  `quest_id`       INT(11)     NOT NULL,
  `last_completed` TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP,
  PRIMARY KEY (`faction_id`, `quest_id`),
  CONSTRAINT `fk_cooldown_quest` FOREIGN KEY (`quest_id`) REFERENCES `ax_quests` (`id`) ON DELETE CASCADE
) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci;

-- ─────────────────────────────────────────────────────────────
-- Misiones de ejemplo
-- ─────────────────────────────────────────────────────────────

INSERT INTO `ax_quests` (`name`, `description`, `type`, `difficulty`, `faction_id`, `objective_data`, `rewards`, `is_active`, `created_by`) VALUES
(
  'Suministros para los Militares',
  'Los militares necesitan materiales urgentes. Reúne y entrega los suministros al Sargento Reyes.',
  'DELIVERY', 'medium', NULL,
  '{"items":[{"name":"scrap","amount":400,"label":"Chatarra"},{"name":"radio","amount":3,"label":"Radios"},{"name":"engine","amount":2,"label":"Motores"}]}',
  '{"money":15000,"items":[{"name":"bandage","amount":10}],"xp":250}',
  1, 'console'
),
(
  'Limpieza de Zona Norte',
  'Una horda de infectados ha tomado el perímetro norte. Elimínalos antes de que se expandan.',
  'TERRITORY', 'hard', NULL,
  '{"zone":{"x":1204.5,"y":2831.0,"z":44.0,"radius":80.0},"kills_required":50}',
  '{"money":20000,"items":[{"name":"ammo_rifle","amount":100}],"xp":500}',
  1, 'console'
);