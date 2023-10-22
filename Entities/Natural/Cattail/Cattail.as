void onInit(CBlob@ this)
{
	this.getShape().SetStatic(true);
	this.Tag("needs_init");

	this.set_u16("frame_iter", 0);
	this.set_bool("anim_backwards", false);

	this.setAngleDegrees(90*XORRandom(5));

	this.getCurrentScript().tickFrequency = 90;
}

void initSprite(CSprite@ this)
{
	this.SetZ(550.0f);

	CBlob@ blob = this.getBlob();
	if (blob is null) return;

	CSpriteLayer@ innerlayer = this.addSpriteLayer("innerlayer", this.getConsts().filename, 16, 16);
	if (innerlayer !is null)
	{
		Animation@ anim = innerlayer.addAnimation("default", 0, false);
		if (anim !is null)
		{
			anim.AddFrame(3);
			innerlayer.SetAnimation("default");
			innerlayer.SetRelativeZ(-500.0f);
			innerlayer.SetVisible(false);
		}
	}

	// mid
	u8 rand = XORRandom(100);
	Animation@ anim = this.addAnimation("variety", 150+XORRandom(300), true);
	int[] frames = {0,1,2};
	if (rand > 66) 
	{
		int[] frames = {8,9,10};
	}
	else if (rand > 33)
	{
		int[] frames = {16,17,18};
	}
	anim.AddFrames(frames);
	this.SetAnimation("variety");
	this.animation.frame = XORRandom(3);

	blob.Untag("needs_init");
}

void onTick(CSprite@ this)
{
	CBlob@ blob = this.getBlob();
	if (blob is null || !blob.isOnScreen()) return;

	if (blob.hasTag("needs_init"))
		initSprite(this);
}

void onCollision(CBlob@ this, CBlob@ blob, bool solid)
{
	if (isClient() && blob !is null)
	{
		this.getSprite().animation.frame += 1;

		CSpriteLayer@ innerlayer = this.getSprite().getSpriteLayer("innerlayer");
		if (blob.isMyPlayer() && innerlayer !is null)
		{
			innerlayer.SetVisible(true);
			this.SetVisible(false);
		}
	}
}

void onEndCollision(CBlob@ this, CBlob@ blob)
{
	if (isClient() && blob !is null)
	{
		CSpriteLayer@ innerlayer = this.getSprite().getSpriteLayer("innerlayer");
		if (blob.isMyPlayer() && innerlayer !is null)
		{
			innerlayer.SetVisible(false);
			this.SetVisible(true);
		}
	}
}