#include "ExplosionEffects.as";;
#include "DamageBooty.as";
#include "AccurateSoundPlay.as";
#include "ParticleSpark.as";
#include "Hitters.as";
#include "PlankCommon.as";
#include "TileCommon.as";
#include "WaterEffects.as";

const f32 EXPLODE_RADIUS = 30.0f;
const f32 FLAK_REACH = 50.0f;

BootyRewards@ booty_reward;

void onInit(CBlob@ this)
{
	if (booty_reward is null)
	{
		BootyRewards _booty_reward;
		_booty_reward.addTagReward("bomb", 4);
		_booty_reward.addTagReward("engine", 2);
		_booty_reward.addTagReward("mothership", 8);
		_booty_reward.addTagReward("secondarycore", 6);
		_booty_reward.addTagReward("weapon", 5);
		@booty_reward = _booty_reward;
	}
	
	this.Tag("flak shell");
	this.Tag("projectile");

	ShapeConsts@ consts = this.getShape().getConsts();
	consts.mapCollisions = true;
	consts.bullet = true;

	this.getSprite().SetZ(550.0f);
	
	//shake screen (onInit accounts for firing latency)
	CPlayer@ localPlayer = getLocalPlayer();
	if (localPlayer !is null && localPlayer is this.getDamageOwnerPlayer())
		ShakeScreen(4, 4, this.getPosition());
}

void onTick(CBlob@ this)
{
	if (!isServer()) return;
	
	bool killed = false;

	Vec2f pos = this.getPosition();
	const int thisColor = this.get_u32("color");
}

void onDie(CBlob@ this)
{
	Vec2f pos = this.getPosition();
	
	if (isClient())
	{
		if (!isInWater(pos))
		{
			sparks(pos + this.getVelocity(), v_fastrender ? 5 : 15, 2.5, 20);
			directionalSoundPlay("MetalImpact" + (XORRandom(2) + 1), pos);
		}
		else if (this.getTouchingCount() <= 0)
		{
			MakeWaterParticle(pos, Vec2f_zero);
			directionalSoundPlay("WaterSplashBall.ogg", pos);
		}
	}
}

void onHitBlob(CBlob@ this, Vec2f worldPoint, Vec2f velocity, f32 damage, CBlob@ hitBlob, u8 customData)
{
	CPlayer@ owner = this.getDamageOwnerPlayer();
	if (owner !is null)
	{
		CBlob@ blob = owner.getBlob();
		if (blob !is null)
			rewardBooty(owner, hitBlob, booty_reward);
	}
	
	if (!isClient()) return;
	
	if (customData == 9 || damage <= 0.0f) return;

	if (hitBlob.hasTag("solid") || hitBlob.hasTag("core") || hitBlob.hasTag("door") || hitBlob.hasTag("seat") || hitBlob.hasTag("weapon"))
	{
		directionalSoundPlay("Pierce1.ogg", worldPoint);
			
		if (hitBlob.hasTag("mothership"))
			directionalSoundPlay("Entities/Characters/Knight/ShieldHit.ogg", worldPoint);
	}
}

void onCollision(CBlob@ this, CBlob@ b, bool solid, Vec2f normal, Vec2f point1)
{
	if (this.hasTag("killed")) return;
	if (b is null) //solid tile collision
	{
		if (isClient())
		{
			sparks(point1, v_fastrender ? 5 : 15, 2.5f, 20);
			directionalSoundPlay("MetalImpact" + (XORRandom(2) + 1), point1);
		}
		this.server_Die();
		return;
	}
	
	if (b.hasTag("plank") && !CollidesWithPlank(b, this.getVelocity()))
		return;

	bool killed = false;
	const int color = b.getShape().getVars().customData;
	const bool sameTeam = b.getTeamNum() == this.getTeamNum();
	const bool isBlock = b.hasTag("block");
	
	if (color > 0 || !isBlock)
	{
		if (isBlock)
		{
			if (b.hasTag("solid") || (b.hasTag("door") && b.getShape().getConsts().collidable) || 
				(!sameTeam && (b.hasTag("core") || b.hasTag("weapon") || b.hasTag("bomb")))) //hit these and die
			{
				sparksDirectional(this.getPosition() + this.getVelocity(), this.getVelocity(), v_fastrender ? 4 : 7);
				killed = true;
			}
			else if (b.hasTag("hasSeat"))
			{
				AttachmentPoint@ seat = b.getAttachmentPoint(0);
				CBlob@ occupier = seat.getOccupied();
				if (occupier !is null && occupier.getName() == "human" && occupier.getTeamNum() != this.getTeamNum())
				{
					killed = true;
				}
				else return;
			}
			else return;
		}
		else
		{
			if (sameTeam || (b.hasTag("player") && b.isAttached()) || b.hasTag("projectile")) //don't hit
				return;
		}
		
		if (!isServer()) return;
		this.server_Hit(b, point1, Vec2f_zero, getDamage(this, b), Hitters::ballista, true);
		
		if (killed) 
		{
			this.Tag("killed");
			this.server_Die(); 
			return;
		}
	}
}

const f32 getDamage(CBlob@ this, CBlob@ hitBlob)
{
	if (hitBlob.hasTag("bomb"))
		return 2.0f;
	if (hitBlob.hasTag("ramengine"))
		return 1.25f;
	if (hitBlob.hasTag("propeller"))
		return 0.5f;
	if (hitBlob.hasTag("seat") || hitBlob.hasTag("plank"))
		return 0.5f;
	if (hitBlob.hasTag("weapon"))
		return 0.35f;
	if (hitBlob.getName() == "shark" || hitBlob.getName() == "human")
		return 0.5f;
	if (hitBlob.hasTag("mothership"))
		return 0.33f;

	return 0.25f;
}

Random _sprk_r;
void sparksDirectional(const Vec2f&in pos, Vec2f&in blobVel, const u8&in amount)
{
	for (u8 i = 0; i < amount; i++)
	{
		Vec2f vel(_sprk_r.NextFloat() * 5.0f, 0);
		vel.RotateBy((-blobVel.getAngle() + 180.0f) + _sprk_r.NextFloat() * 30.0f - 15.0f);

		CParticle@ p = ParticlePixel(pos, vel, SColor( 255, 255, 128+_sprk_r.NextRanged(128), _sprk_r.NextRanged(128)), true);
		if (p is null) return; //bail if we stop getting particles

		p.timeout = 20 + _sprk_r.NextRanged(20);
		p.scale = 1.0f + _sprk_r.NextFloat();
		p.damping = 0.85f;
		p.Z = 650.0f;
	}
}