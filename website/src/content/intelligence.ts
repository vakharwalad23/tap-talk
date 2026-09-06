export interface RewriteMode {
	readonly name: string;
	readonly description: string;
	readonly example: {
		readonly raw: string;
		readonly result: string;
		readonly target: string;
	};
}

export const intelligence = {
	title: "It does not just transcribe. It writes it the way you would.",
	intro:
		"Hold the Smart key instead of the normal one and TapTalk runs a local language model over your transcript, cleaning it up and shaping it to fit wherever you are typing. It runs on your Mac by default (Qwen 2.5 1.5B via llama.cpp), or you can point it at your own endpoint.",
	backends:
		"Fully local by default (runs offline on the Metal GPU), or bring your own: Ollama, LM Studio, or OpenAI.",
	precedenceNote:
		"Match the app already removes filler and resolves corrections, so it replaces the other two while it is on.",
} as const;

export const rewriteModes: readonly RewriteMode[] = [
	{
		name: "Polish",
		description:
			"Removes um, uh and false starts. Fixes grammar, keeps your wording.",
		example: {
			raw: "hey can you uh push the fix to staging and um lemme know",
			result: "Hey, can you push the fix to staging and let me know?",
			target: "Slack",
		},
	},
	{
		name: "Restructure",
		description: "You said 10am then corrected to 11am, only 11am is pasted.",
		example: {
			raw: "meeting at 10 no sorry 11 with the design team",
			result: "Meeting at 11 with the design team.",
			target: "Notes",
		},
	},
	{
		name: "Match the app",
		description:
			"Casual in Slack, a shell command in Terminal, prose in Notes.",
		example: {
			raw: "list all the docker containers even the stopped ones",
			result: "docker ps -a",
			target: "Terminal",
		},
	},
];

export const hinglish = {
	title: "Dictate in Hindi. Get Hinglish. On-device.",
	intro:
		"Most dictation apps either do Hindi poorly or send it to the cloud. TapTalk transcribes Hindi (and Marathi, Urdu, Chinese, Japanese, and more) locally with NVIDIA's Nemotron model, and can hand you natural Roman-script Hinglish, the way people actually chat. All on your Mac.",
	// The only intentional non-ASCII text on the site: a real Hindi input sample.
	spoken: "कल मीटिंग है, please report भेज देना",
	result: "kal meeting hai, please report bhej dena",
	caption: "English words stay English. No clumsy transliteration.",
	honesty:
		"TapTalk only offers languages its model can truly produce, so you never get garbage output from an unsupported script.",
} as const;
