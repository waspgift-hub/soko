// Profanity detection (ported verbatim from the legacy server).
const PROFANITY_LIST = [
  'kuma','pussy','fuck','shit','bitch','ass','dick','cock','penis','vagina',
  'nigger','nigga','faggot','retard','cunt','whore','slut','bastard','damn',
  'wewe ni kuma','mtu wa kuma','mjinga','mshenzi','mbwa','zuzu','fala',
  'chumbani','jogoo','kinyama','mavi','taka taka','kenyeje',
  'uchafu','uchawi','ugomvi','upidifu','uzimu',
  'punda','ng\'ombe','kondoo','mbuzi','kuku',
  'mzezende','mjinga sana','kigogo','mshamba',
  'figa','uchungu',
  'tembo','kiboko','nyoka','mamba','fisi',
];

function containsProfanity(text) {
  if (!text || typeof text !== 'string') return false;
  const lower = text.toLowerCase().replace(/[0-9]/g, '');
  const words = lower.split(/[\s,.\-!?;:'"()\/]+/).filter(Boolean);
  for (const word of words) {
    if (PROFANITY_LIST.includes(word)) return true;
  }
  const phrases = PROFANITY_LIST.filter((p) => p.includes(' '));
  for (const phrase of phrases) {
    if (lower.includes(phrase)) return true;
  }
  return false;
}

module.exports = { PROFANITY_LIST, containsProfanity };
