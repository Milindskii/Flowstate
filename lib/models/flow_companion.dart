import 'package:flutter/material.dart';

/// Flow Companion Model
/// Represents the persistent animal companion (🦊 Noya) that grows
/// through validated focus time and real productive behavior.
class FlowCompanion {
  final String id;
  final String species;
  final String name;
  final int level;
  final String stage;
  final int companionXp;
  final int xpToNextLevel;
  final bool isEvolutionReady;
  final bool isActive;
  final String cosmeticState;

  const FlowCompanion({
    required this.id,
    this.species = 'fox',
    this.name = 'Noya',
    this.level = 1,
    this.stage = 'Baby',
    this.companionXp = 0,
    this.xpToNextLevel = 60,
    this.isEvolutionReady = false,
    this.isActive = true,
    this.cosmeticState = '{}',
  });

  /// Fraction of XP toward next level (0.0 to 1.0)
  double get progressFraction {
    final totalLevelBand = companionXp + xpToNextLevel;
    if (totalLevelBand <= 0) return 0.0;
    final frac = companionXp / totalLevelBand;
    return frac.clamp(0.0, 1.0);
  }

  CompanionAnimalInfo get animalInfo => CompanionAnimalInfo.fromSpecies(species);

  String get speciesEmoji => animalInfo.emoji;

  String get stageBadge => '$speciesEmoji $name · Level $level';

  FlowCompanion copyWith({
    String? id,
    String? species,
    String? name,
    int? level,
    String? stage,
    int? companionXp,
    int? xpToNextLevel,
    bool? isEvolutionReady,
    bool? isActive,
    String? cosmeticState,
  }) {
    return FlowCompanion(
      id: id ?? this.id,
      species: species ?? this.species,
      name: name ?? this.name,
      level: level ?? this.level,
      stage: stage ?? this.stage,
      companionXp: companionXp ?? this.companionXp,
      xpToNextLevel: xpToNextLevel ?? this.xpToNextLevel,
      isEvolutionReady: isEvolutionReady ?? this.isEvolutionReady,
      isActive: isActive ?? this.isActive,
      cosmeticState: cosmeticState ?? this.cosmeticState,
    );
  }

  factory FlowCompanion.fromJson(Map<String, dynamic> json) {
    return FlowCompanion(
      id: json['id'] as String? ?? 'companion-default',
      species: json['species'] as String? ?? 'fox',
      name: json['name'] as String? ?? 'Noya',
      level: json['level'] as int? ?? 1,
      stage: json['stage'] as String? ?? 'Baby',
      companionXp: json['companion_xp'] as int? ?? 0,
      xpToNextLevel: json['xp_to_next_level'] as int? ?? 60,
      isEvolutionReady: json['is_evolution_ready'] as bool? ?? false,
      isActive: json['is_active'] as bool? ?? true,
      cosmeticState: json['cosmetic_state'] as String? ?? '{}',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'species': species,
      'name': name,
      'level': level,
      'stage': stage,
      'companion_xp': companionXp,
      'xp_to_next_level': xpToNextLevel,
      'is_evolution_ready': isEvolutionReady,
      'is_active': isActive,
      'cosmetic_state': cosmeticState,
    };
  }
}

/// Rich details, lore, focus perks, and evolution line for each companion species
class CompanionAnimalInfo {
  final String species;
  final String defaultName;
  final String emoji;
  final String title;
  final String motto;
  final String description;
  final String personality;
  final String perk;
  final Color accentColor;
  final List<String> evolutionLine;

  const CompanionAnimalInfo({
    required this.species,
    required this.defaultName,
    required this.emoji,
    required this.title,
    required this.motto,
    required this.description,
    required this.personality,
    required this.perk,
    required this.accentColor,
    required this.evolutionLine,
  });

  static const fox = CompanionAnimalInfo(
    species: 'fox',
    defaultName: 'Noya',
    emoji: '🦊',
    title: 'The Swift Sprinter',
    motto: 'Light on your feet, sharp in your mind.',
    description: 'Curious, agile, and razor-sharp. Noya thrives during high-energy focus windows and quick sprint bursts.',
    personality: 'Alert, curious, encouraging, and playful. Noya nudges you gently when you drift and celebrates small wins.',
    perk: 'Sprint Mastery (+15% focus clarity during 25m Pomodoro sprints)',
    accentColor: Color(0xFFF97316),
    evolutionLine: ['Kit Noya', 'Swift Noya', 'Nomad Noya', 'Astral Fox', 'Celestial Kitsune'],
  );

  static const otter = CompanionAnimalInfo(
    species: 'otter',
    defaultName: 'Ludo',
    emoji: '🦦',
    title: 'The Flow Navigator',
    motto: 'Smooth waters run deep. Drift with the current, not the chaos.',
    description: 'Playful, resilient, and fluid. Ludo washes away anxiety and keeps your focus rhythm smooth over long blocks.',
    personality: 'Grounded, adaptable, cheerful, and smooth. Keeps momentum steady and turns challenging tasks into enjoyable play.',
    perk: 'Deep Current (Maintains steady momentum through 45–60m continuous sessions)',
    accentColor: Color(0xFF06B6D4),
    evolutionLine: ['Pup Ludo', 'River Ludo', 'Wave Ludo', 'Torrent Otter', 'Tide Sovereign'],
  );

  static const owl = CompanionAnimalInfo(
    species: 'owl',
    defaultName: 'Aria',
    emoji: '🦉',
    title: 'The Deep Scholar',
    motto: 'Silence cuts through distraction. Insight arrives in stillness.',
    description: 'Calm, observant, and wise. Aria masters late-night or early-morning uninterrupted deep work and intricate problem solving.',
    personality: 'Serene, observant, dignified, and perceptive. Helps you eliminate ambient noise and spot breakthroughs.',
    perk: 'Night Owl & Insight (Peak clarity during complex problem-solving and quiet study)',
    accentColor: Color(0xFF8B5CF6),
    evolutionLine: ['Owlet Aria', 'Fledgling Aria', 'Nightwing Aria', 'Archon Owl', 'Celestial Seraph'],
  );

  static const capybara = CompanionAnimalInfo(
    species: 'capybara',
    defaultName: 'Boba',
    emoji: '🐾',
    title: 'The Zen Anchor',
    motto: 'Nothing is an emergency. Stay centered and steady.',
    description: 'Unshakeable serenity and warmth. Boba is the ultimate antidote to deadline panic and high-friction backlogs.',
    personality: 'Peaceful, warm, unbothered, and steadfast. Balances heavy workloads with emotional calm.',
    perk: 'Stress Immunity (Eliminates overwhelm when tackling high-priority backlogs)',
    accentColor: Color(0xFF10B981),
    evolutionLine: ['Bean Boba', 'Warm Spring Boba', 'Grove Boba', 'Elder Capy', 'Nirvana Sovereign'],
  );

  static const cat = CompanionAnimalInfo(
    species: 'cat',
    defaultName: 'Mochi',
    emoji: '🐱',
    title: 'The Creative Muse',
    motto: 'Curiosity unlocks delight. Play with your ideas.',
    description: 'Playful, curious, and sweet. Mochi turns light work and creative drafting into effortless joy.',
    personality: 'Playful, creative, lighthearted, and affectionate.',
    perk: 'Creative Flow (Boosts energy recovery during light work and brainstorming)',
    accentColor: Color(0xFFF472B6),
    evolutionLine: ['Kitten Mochi', 'Whiskers Mochi', 'Calico Mochi', 'Astra Cat', 'Celestial Neko'],
  );

  static const List<CompanionAnimalInfo> all = [fox, otter, owl, capybara];

  static CompanionAnimalInfo fromSpecies(String species) {
    switch (species.toLowerCase()) {
      case 'otter':
        return otter;
      case 'owl':
        return owl;
      case 'capybara':
        return capybara;
      case 'cat':
      case 'mochi':
        return cat;
      case 'fox':
      default:
        return fox;
    }
  }
}
