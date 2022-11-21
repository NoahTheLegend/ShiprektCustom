f32 COOLDOWN_SECONDS = 7.5f;

void onInit(CBlob@ this)
{
	this.Tag("solid");
	
	this.set_f32("weight", 1.5f);
	
	this.set_f32("power", 0.0f);
	this.set_f32("powerFactor", 1.75f);
	this.set_u32("onTime", 0);
	this.set_u8("stallTime", 0);
	this.set_u32("cooldown", 0);

	this.Tag("booster");

	this.addCommandID("chainReaction");
	this.addCommandID("activate");
	this.set_u32("workingTime", 0);

	CSprite@ sprite = this.getSprite();
	CSpriteLayer@ propeller = sprite.addSpriteLayer("propeller");
	if (propeller !is null)
	{
		propeller.SetOffset(Vec2f(0,8));
		propeller.SetRelativeZ(2);
		propeller.SetLighting(false);
		Animation@ animcharge = propeller.addAnimation("go", 1, true);
		animcharge.AddFrame(3);
		animcharge.AddFrame(4);
		propeller.SetAnimation("go");
	}

	sprite.SetEmitSound("PropellerMotor");
	sprite.SetEmitSoundPaused(true);
}

void onTick(CBlob@ this)
{
	if (this.hasTag("activated"))
	{
		if (this.get_u32("workingTime") > getGameTime())
		{
			this.set_u32("onTime", getGameTime());
			this.set_f32("power", this.get_f32("power") * this.get_f32("powerFactor"));
		}
		else
		{
			this.set_u32("onTime", 0);
			this.set_f32("power", 0);
			this.Untag("activated");
			this.set_u32("cooldown", getGameTime() + COOLDOWN_SECONDS*30);
		}
	}
}

void Activate(CBlob@ this, const u32&in time)
{
	if (this.hasTag("activated") || this.get_u32("cooldown") > getGameTime()) return;
	this.Tag("activated");
	this.set_u32("workingTime", time);
}

void ChainReaction(CBlob@ this, const u32&in time)
{
	if (this.hasTag("activated") || this.get_u32("cooldown") > getGameTime()) return;
	CBitStream bs;
	bs.write_u32(time);
	this.SendCommand(this.getCommandID("activate"), bs);

	CBlob@[] overlapping;
	this.getOverlapping(@overlapping);
	
	const u8 overlappingLength = overlapping.length;
	for (u8 i = 0; i < overlappingLength; i++)
	{
		CBlob@ b = overlapping[i];
		if (b.hasTag("booster") && !b.hasTag("activated") && b.getShape().getVars().customData > 0 && b.getDistanceTo(this) < 8.8f)
		{
			ChainReaction(b, time);
		}
	}
}

void onCommand(CBlob@ this, u8 cmd, CBitStream@ params)
{
	if (cmd == this.getCommandID("activate") && !this.hasTag("activated"))
		Activate(this, params.read_u32());
	else if (isServer() && cmd == this.getCommandID("chainReaction") && !this.hasTag("activated"))
		ChainReaction(this, getGameTime() + 75);
}