import { faq } from "#/content/faq";
import { setupSteps } from "#/content/setup";
import { site } from "#/content/site";

type JsonLd = Record<string, unknown>;

function softwareApplication(): JsonLd {
	return {
		"@context": "https://schema.org",
		"@type": "SoftwareApplication",
		name: site.name,
		applicationCategory: "UtilitiesApplication",
		operatingSystem: "macOS 14.0 or later, Apple Silicon",
		description: site.shortDescription,
		url: site.url,
		downloadUrl: site.downloadUrl,
		softwareVersion: site.version,
		license: site.licenseUrl,
		isAccessibleForFree: true,
		offers: { "@type": "Offer", price: "0", priceCurrency: "USD" },
		author: { "@type": "Person", name: site.authorName, url: site.authorUrl },
		sameAs: [site.repoUrl],
		dateModified: site.lastUpdated,
	};
}

function faqPage(): JsonLd {
	return {
		"@context": "https://schema.org",
		"@type": "FAQPage",
		mainEntity: faq.map((item) => ({
			"@type": "Question",
			name: item.question,
			acceptedAnswer: { "@type": "Answer", text: item.answer },
		})),
	};
}

function howTo(): JsonLd {
	return {
		"@context": "https://schema.org",
		"@type": "HowTo",
		name: "How to set up TapTalk on your Mac",
		description:
			"Install TapTalk, download an on-device model, grant two permissions, and dictate into any app.",
		totalTime: "PT2M",
		step: setupSteps.map((step, index) => ({
			"@type": "HowToStep",
			position: index + 1,
			name: step.optional ? `${step.title} (optional)` : step.title,
			text: step.note ? `${step.body} ${step.note}` : step.body,
		})),
	};
}

function webSite(): JsonLd {
	return {
		"@context": "https://schema.org",
		"@type": "WebSite",
		name: site.name,
		url: site.url,
		author: { "@type": "Person", name: site.authorName, url: site.authorUrl },
	};
}

export function jsonLdScripts(): ReadonlyArray<{
	type: string;
	children: string;
}> {
	return [softwareApplication(), faqPage(), howTo(), webSite()].map((data) => ({
		type: "application/ld+json",
		children: JSON.stringify(data),
	}));
}
