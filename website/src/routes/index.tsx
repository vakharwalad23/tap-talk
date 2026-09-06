import { createFileRoute } from "@tanstack/react-router";
import { type ReactNode, Suspense } from "react";
import { useReveal } from "#/components/interactive/useReveal";
import { AppReplicas } from "#/components/replicas/AppReplicas";
import { Comparison } from "#/components/sections/Comparison";
import { Faq } from "#/components/sections/Faq";
import { Features } from "#/components/sections/Features";
import { FinalCta } from "#/components/sections/FinalCta";
import { Footer } from "#/components/sections/Footer";
import { Hero } from "#/components/sections/Hero";
import { HowItWorks } from "#/components/sections/HowItWorks";
import { Intelligence } from "#/components/sections/Intelligence";
import { Multilingual } from "#/components/sections/Multilingual";
import { Nav } from "#/components/sections/Nav";
import { OpenSource } from "#/components/sections/OpenSource";
import { PillShowcase } from "#/components/sections/PillShowcase";
import { Privacy } from "#/components/sections/Privacy";
import { Setup } from "#/components/sections/Setup";
import { Speed } from "#/components/sections/Speed";
import { Tech } from "#/components/sections/Tech";
import { ValueTiles } from "#/components/sections/ValueTiles";
import { WorksEverywhere } from "#/components/sections/WorksEverywhere";

export const Route = createFileRoute("/")({ component: Home });

// Each section below the fold gets its own Suspense boundary. Nothing suspends on the server,
// so the prerendered HTML is complete; on the client React hydrates boundary by boundary
// instead of in one long task.
function Island({ children }: { readonly children: ReactNode }) {
	return <Suspense fallback={null}>{children}</Suspense>;
}

const sections = [
	ValueTiles,
	HowItWorks,
	PillShowcase,
	Features,
	Speed,
	Intelligence,
	Multilingual,
	WorksEverywhere,
	AppReplicas,
	Comparison,
	Privacy,
	OpenSource,
	Setup,
	Tech,
	Faq,
	FinalCta,
] as const;

function Home() {
	useReveal();
	return (
		<>
			<Nav />
			<main id="main">
				<Hero />
				{sections.map((Section) => (
					<Island key={Section.name}>
						<Section />
					</Island>
				))}
			</main>
			<Island>
				<Footer />
			</Island>
		</>
	);
}
