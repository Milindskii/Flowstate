import 'package:flutter_test/flutter_test.dart';
import 'package:flowstate/models/personal_data.dart';
import 'package:flowstate/engines/readiness_engine.dart';
import 'package:flowstate/engines/scheduling_engine.dart';
import 'package:flowstate/providers/app_state_provider.dart';

void main() {
  group('Personalization and Learning Engine Tests', () {
    test('1. Afternoon focus peak reflects 2:00 PM – 5:00 PM in ReadinessEngine', () {
      const personalData = PersonalData(
        sleepHours: 8.0,
        wakeTime: '07:30',
        sleepQuality: 'Deep & Restful',
        focusPeak: 'Afternoon',
        energyDipTime: '11:30 AM',
        physicalActivityMinutes: 30,
        primaryGoal: 'Work',
      );

      final readiness = const ReadinessEngine().computeReadiness(
        personalData: personalData,
      );

      expect(readiness.focusWindowRange, '2:00 PM – 5:00 PM');
    });

    test('2. Case-insensitive afternoon peak reflects 2:00 PM – 5:00 PM in ReadinessEngine', () {
      const personalData = PersonalData(
        sleepHours: 7.5,
        wakeTime: '08:00',
        sleepQuality: 'Moderate',
        focusPeak: 'afternoon',
        energyDipTime: '11:00 AM',
        physicalActivityMinutes: 20,
        primaryGoal: 'General productivity',
      );

      final readiness = const ReadinessEngine().computeReadiness(
        personalData: personalData,
      );

      expect(readiness.focusWindowRange, '2:00 PM – 5:00 PM');
    });

    test('3. PlanningProfile.fromPersonalData creates afternoon peak window at 14:00 - 17:00', () {
      const personalData = PersonalData(
        sleepHours: 8.0,
        wakeTime: '07:00',
        sleepQuality: 'Deep & Restful',
        focusPeak: 'afternoon',
        energyDipTime: '11:00 AM',
        physicalActivityMinutes: 30,
        primaryGoal: 'Work',
      );

      final profile = PlanningProfile.fromPersonalData(personalData);

      expect(profile.peakWindowStart, 14.0);
      expect(profile.peakWindowEnd, 17.0);
      expect(profile.wakeTime, 7.0);
    });

    test('4. AppStateProvider updatePersonalData propagates afternoon peak to readiness', () {
      final appState = AppStateProvider();
      expect(appState.readiness.focusWindowRange, isNotNull);

      appState.updatePersonalData(
        appState.personalData.copyWith(focusPeak: 'Afternoon'),
      );

      expect(appState.readiness.focusWindowRange, '2:00 PM – 5:00 PM');
    });
  });
}
