-- ============================================================
--  AX_QuestCreator | install.sql
--  Ejecutar una sola vez en tu base de datos
-- ============================================================

CREATE TABLE IF NOT EXISTS `ax_quests` (
  `id`               INT(11)      NOT NULL AUTO_INCREMENT,
  `name`             VARCHAR(100) NOT NULL,
  `description`      TEXT         NOT NULL,
  `type`             ENUM('ELIMINATE','COLLECT','DEFEND','REPAIR') NOT NULL,
  `difficulty`       ENUM('easy','medium','hard','extreme') NOT NULL DEFAULT 'easy',
  `faction_id`       VARCHAR(50)  DEFAULT NULL COMMENT 'NULL = disponible para todas las facciones',
  `min_players`      INT(2)       NOT NULL DEFAULT 1,
  `max_players`      INT(2)       NOT NULL DEFAULT 10,
  `objective_data`   JSON         NOT NULL COMMENT 'Datos específicos según tipo de misión',
  `rewards`          JSON         NOT NULL COMMENT '{"money": 5000, "items": [{"name":"item","amount":1}]}',
  `time_limit`       INT(6)       DEFAULT NULL COMMENT 'Segundos. NULL = sin límite',
  `cooldown_minutes` INT(6)       NOT NULL DEFAULT 60,
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
  `accepted_by`  VARCHAR(50) NOT NULL COMMENT 'identifier del jugador que aceptó',
  `status`       ENUM('active','completed','failed','expired') NOT NULL DEFAULT 'active',
  `progress`     JSON        NOT NULL DEFAULT '{}' COMMENT 'Progreso actual según tipo',
  `started_at`   TIMESTAMP   NOT NULL DEFAULT CURRENT_TIMESTAMP,
  `completed_at` TIMESTAMP   NULL DEFAULT NULL,
  `expires_at`   TIMESTAMP   NULL DEFAULT NULL COMMENT 'NULL si no tiene tiempo límite',
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

INSERT INTO `ax_quests` (`name`, `description`, `type`, `difficulty`, `faction_id`, `min_players`, `max_players`, `objective_data`, `rewards`, `time_limit`, `cooldown_minutes`, `is_active`, `created_by`) VALUES
(
  'Limpieza de Zona',
  'Un sector al norte ha sido invadido por hordas de infectados. Elimina la amenaza y asegura el perímetro.',
  'ELIMINATE', 'medium', NULL, 1, 6,
  '{"amount": 15, "zone": {"x": 1204.5, "y": 2831.0, "z": 44.0, "radius": 80.0}}',
  '{"money": 5000, "items": [{"name": "bandage", "amount": 3}]}',
  600, 60, 1, 'console'
),
(
  'Recuperar Suministros',
  'Un convoy fue emboscado. Los suministros médicos están dispersos en la zona. Recupéralos antes de que caigan en manos equivocadas.',
  'COLLECT', 'hard', NULL, 2, 4,
  '{"item": "medical_supply", "amount": 5, "zone": {"x": -432.0, "y": -1700.0, "z": 19.0, "radius": 60.0}, "drop_on_kill": false}',
  '{"money": 8000, "items": [{"name": "water", "amount": 5}, {"name": "bandage", "amount": 5}]}',
  900, 90, 1, 'console'
),
(
  'Defender la Base',
  'Inteligencia reporta un ataque inminente al punto de control. Mantén la posición el tiempo necesario.',
  'DEFEND', 'hard', NULL, 3, 8,
  '{"zone": {"x": 1097.0, "y": 2640.0, "z": 37.0, "radius": 50.0}, "duration_seconds": 300, "min_players_inside": 2}',
  '{"money": 12000, "items": [{"name": "ammo_pistol", "amount": 50}]}',
  NULL, 120, 1, 'console'
),
(
  'Reparación de Infraestructura',
  'Los generadores del campamento fallaron. Localiza y repara los puntos de fallo antes de que caiga la noche.',
  'REPAIR', 'easy', NULL, 1, 3,
  '{"points": [{"x": 1082.0, "y": 2820.0, "z": 37.0, "label": "Generador A"}, {"x": 1115.0, "y": 2798.0, "z": 37.0, "label": "Generador B"}], "interact_time": 12000}',
  '{"money": 3000, "items": [{"name": "toolkit", "amount": 1}]}',
  480, 45, 1, 'console'
);